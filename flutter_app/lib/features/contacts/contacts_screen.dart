/// Contacts: list/detail, search, filters, CSV import/export, dedupe/merge.
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme.dart';
import '../../core/util/csv_io.dart';
import '../../core/util/phone.dart';
import '../../data/repositories/app_repository.dart';
import '../../domain/models/models.dart';
import '../../providers.dart';
import 'package:collection/collection.dart';

class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  String query = '';
  String tagFilter = 'all';
  String? selectedId;

  @override
  Widget build(BuildContext context) {
    final s = stateOf(ref);
    final wide = MediaQuery.of(context).size.width >= 1000;
    final tags = {'all', for (final c in s.contacts) ...c.tags};
    var contacts = s.contacts.where((c) => !c.archived).toList()
      ..sort((a, b) {
        if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
        return a.lastName.compareTo(b.lastName);
      });
    if (query.isNotEmpty) {
      contacts = contacts
          .where((c) =>
              c.displayName.toLowerCase().contains(query.toLowerCase()) ||
              c.phones.any((p) => p.e164.contains(query)) ||
              c.emails.any((e) => e.contains(query.toLowerCase())))
          .toList();
    }
    if (tagFilter != 'all') {
      contacts = contacts.where((c) => c.tags.contains(tagFilter)).toList();
    }
    final selected = s.contacts.where((c) => c.id == selectedId).firstOrNull;
    final dupes = findDuplicates(s.contacts);

    final listPanel = Column(children: [
      Padding(
        padding: const EdgeInsets.all(10),
        child: Row(children: [
          Expanded(
            child: TextField(
              decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search, size: 16),
                  hintText: 'Search contacts',
                  isDense: true),
              onChanged: (v) => setState(() => query = v),
            ),
          ),
          const SizedBox(width: 8),
          DropdownButton<String>(
            value: tagFilter,
            items: [for (final t in tags) DropdownMenuItem(value: t, child: Text(t))],
            onChanged: (v) => setState(() => tagFilter = v ?? 'all'),
          ),
        ]),
      ),
      Wrap(spacing: 8, children: [
        FilledButton.tonalIcon(
            onPressed: _newContact,
            icon: const Icon(Icons.person_add, size: 14),
            label: const Text('New')),
        OutlinedButton.icon(
            onPressed: _importCsv,
            icon: const Icon(Icons.upload_file, size: 14),
            label: const Text('Import CSV')),
        OutlinedButton.icon(
            onPressed: _exportCsv,
            icon: const Icon(Icons.download, size: 14),
            label: const Text('Export CSV')),
        if (dupes.isNotEmpty)
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: PowerlineColors.stateRinging),
            onPressed: () => _showDupes(dupes),
            icon: const Icon(Icons.merge, size: 14),
            label: Text('Merge ${dupes.length} dupes'),
          ),
      ]),
      const SizedBox(height: 6),
      Expanded(
        child: ListView.builder(
          itemCount: contacts.length,
          itemBuilder: (c, i) {
            final ct = contacts[i];
            return ListTile(
              dense: true,
              selected: ct.id == selectedId,
              selectedTileColor: PowerlineColors.cobaltDeep.withValues(alpha: 0.12),
              leading: CircleAvatar(
                radius: 14,
                child: Text(ct.firstName.isEmpty ? '?' : ct.firstName[0],
                    style: const TextStyle(fontSize: 12)),
              ),
              title: Row(children: [
                Flexible(child: Text(ct.displayName, overflow: TextOverflow.ellipsis)),
                if (ct.favorite) const Icon(Icons.star, size: 12, color: PowerlineColors.stateRinging),
                if (ct.dnc)
                  const Padding(
                      padding: EdgeInsets.only(left: 4),
                      child: Icon(Icons.block, size: 12, color: PowerlineColors.stateFailed)),
              ]),
              subtitle: Text(
                  ct.primaryPhone == null ? 'no phone' : PhoneNumberUtil.format(ct.primaryPhone!),
                  style: const TextStyle(fontSize: 11)),
              onTap: () => setState(() => selectedId = ct.id),
            );
          },
        ),
      ),
    ]);

    final detail = selected == null
        ? const Center(
            child: Text('Select a contact', style: TextStyle(color: PowerlineColors.textSecondary)))
        : _ContactDetail(contact: selected);

    if (!wide) return selected == null ? listPanel : detail;
    return Row(children: [
      SizedBox(
          width: 360,
          child: DecoratedBox(
              decoration: const BoxDecoration(
                  border: Border(right: BorderSide(color: PowerlineColors.border))),
              child: listPanel)),
      Expanded(child: detail),
    ]);
  }

  void _newContact() {
    final repo = ref.read(appRepositoryProvider);
    final now = DateTime.now();
    final c = Contact(
        id: newId('ct'), firstName: 'New', lastName: 'Contact', createdAt: now, updatedAt: now);
    repo.upsertContact(c, op: 'create');
    setState(() => selectedId = c.id);
  }

  Future<void> _importCsv() async {
    const typeGroup = XTypeGroup(label: 'CSV', extensions: ['csv']);
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return;
    final text = await file.readAsString();
    final repo = ref.read(appRepositoryProvider);
    final result = contactsFromCsv(text, repo.state.contacts, () => newId('ct'));
    for (final c in result.imported) {
      repo.upsertContact(c, op: 'create');
    }
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('CSV import result'),
        content: Text(
            'Imported: ${result.imported.length}\nSkipped duplicates: ${result.skippedDuplicates}\nErrors:\n${result.errors.isEmpty ? '(none)' : result.errors.join('\n')}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('OK'))
        ],
      ),
    );
  }

  Future<void> _exportCsv() async {
    final csv = contactsToCsv(stateOf(ref).contacts);
    final loc = await getSaveLocation(suggestedName: 'powerline_contacts.csv');
    if (loc == null) return;
    await File(loc.path).writeAsString(csv, encoding: utf8);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Exported to ${loc.path}')));
    }
  }

  void _showDupes(List<List<Contact>> dupes) {
    showDialog<void>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('Duplicate contacts'),
        content: SizedBox(
          width: 420,
          child: ListView(shrinkWrap: true, children: [
            for (final g in dupes)
              ListTile(
                title: Text(g.map((c) => c.displayName).join('  +  ')),
                subtitle: Text('Key: ${dedupeKey(g.first)}'),
                trailing: FilledButton(
                  child: const Text('Merge'),
                  onPressed: () {
                    final repo = ref.read(appRepositoryProvider);
                    final merged = mergeContacts(g);
                    repo.upsertContact(merged);
                    for (final c in g.skip(1)) {
                      repo.deleteContact(c.id);
                    }
                    Navigator.pop(dctx);
                  },
                ),
              ),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Close'))],
      ),
    );
  }
}

class _ContactDetail extends ConsumerWidget {
  final Contact contact;
  const _ContactDetail({required this.contact});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = stateOf(ref);
    final repo = ref.read(appRepositoryProvider);
    final company = s.companies.where((c) => c.id == contact.companyId).firstOrNull;
    final calls = s.calls
        .where((c) => c.contactId == contact.id || contact.phones.any((p) => p.e164 == c.remoteE164))
        .take(8)
        .toList();
    final appts = s.appointments.where((a) => a.contactId == contact.id).toList();

    return ListView(padding: const EdgeInsets.all(20), children: [
      Row(children: [
        CircleAvatar(radius: 26, child: Text(contact.firstName.isEmpty ? '?' : contact.firstName[0])),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(contact.displayName,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            Text(
                '${contact.jobTitle ?? ''}${company != null ? ' · ${company.name}' : ''}'
                '${contact.timeZone != null ? ' · ${contact.timeZone}' : ''}',
                style: const TextStyle(color: PowerlineColors.textSecondary, fontSize: 12)),
            Wrap(spacing: 6, children: [
              for (final t in contact.tags) Chip(label: Text(t, style: const TextStyle(fontSize: 10))),
              if (contact.dnc)
                const Chip(
                    label: Text('DNC', style: TextStyle(fontSize: 10)),
                    backgroundColor: PowerlineColors.stateFailed),
              if (contact.smsOptOut)
                const Chip(label: Text('SMS opt-out', style: TextStyle(fontSize: 10))),
            ]),
          ]),
        ),
        IconButton(
          tooltip: contact.favorite ? 'Unfavorite' : 'Favorite',
          icon: Icon(contact.favorite ? Icons.star : Icons.star_border),
          onPressed: () => repo.upsertContact(contact.copyWith(favorite: !contact.favorite)),
        ),
        IconButton(
          tooltip: 'Archive',
          icon: const Icon(Icons.archive_outlined),
          onPressed: () => repo.upsertContact(contact.copyWith(archived: true)),
        ),
      ]),
      const SizedBox(height: 12),
      Wrap(spacing: 8, children: [
        for (final p in contact.phones)
          FilledButton.tonalIcon(
            onPressed: contact.dnc
                ? null
                : () => ref.read(callSessionProvider.notifier).placeDemoCall(p.e164),
            icon: const Icon(Icons.call, size: 14),
            label: Text('${p.label}: ${PhoneNumberUtil.format(p.e164)}'),
          ),
        OutlinedButton.icon(
          onPressed: contact.primaryPhone == null
              ? null
              : () => repo.ensureConversation(contact.primaryPhone!, contactId: contact.id),
          icon: const Icon(Icons.message_outlined, size: 14),
          label: const Text('Message'),
        ),
        OutlinedButton.icon(
          onPressed: contact.primaryPhone == null
              ? null
              : () => repo.addDnc(contact.primaryPhone!, reason: 'marked from contact card'),
          icon: const Icon(Icons.block, size: 14),
          label: const Text('Mark DNC'),
        ),
      ]),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Edit', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextFormField(
                  initialValue: contact.firstName,
                  decoration: const InputDecoration(labelText: 'First name', isDense: true),
                  onFieldSubmitted: (v) => repo.upsertContact(contact.copyWith(firstName: v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  initialValue: contact.lastName,
                  decoration: const InputDecoration(labelText: 'Last name', isDense: true),
                  onFieldSubmitted: (v) => repo.upsertContact(contact.copyWith(lastName: v)),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            TextFormField(
              initialValue: contact.notes,
              decoration: const InputDecoration(
                  labelText: 'Notes (press Enter to save)', isDense: true),
              onFieldSubmitted: (v) => repo.upsertContact(contact.copyWith(notes: v)),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Communication history', style: TextStyle(fontWeight: FontWeight.w700)),
            if (calls.isEmpty)
              const Padding(padding: EdgeInsets.all(8), child: Text('No calls yet')),
            for (final c in calls)
              ListTile(
                dense: true,
                leading: Icon(
                  c.missed ? Icons.phone_missed : Icons.call_made,
                  size: 16,
                  color: c.missed ? PowerlineColors.stateFailed : PowerlineColors.stateConnected,
                ),
                title: Text('${c.direction.name} · ${c.disposition ?? c.finalState.name}'),
                subtitle: Text(
                    '${c.startedAt.month}/${c.startedAt.day} · ${c.durationSeconds}s',
                    style: const TextStyle(fontSize: 11)),
              ),
            if (appts.isNotEmpty) ...[
              const Divider(),
              const Text('Appointments', style: TextStyle(fontWeight: FontWeight.w700)),
              for (final a in appts)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.event, size: 16),
                  title: Text('${a.kind} · ${a.status.name}'),
                  subtitle: Text('${a.startsAt}', style: const TextStyle(fontSize: 11)),
                ),
            ],
          ]),
        ),
      ),
    ]);
  }
}
