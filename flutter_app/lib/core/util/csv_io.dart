/// CSV import/export + duplicate detection for contacts.
library;

import 'package:csv/csv.dart';

import '../../domain/models/models.dart';
import 'phone.dart';

class CsvImportResult {
  final List<Contact> imported;
  final List<String> errors;
  final int skippedDuplicates;
  const CsvImportResult(this.imported, this.errors, this.skippedDuplicates);
}

String contactsToCsv(List<Contact> contacts) {
  final rows = <List<dynamic>>[
    [
      'firstName',
      'lastName',
      'phone',
      'email',
      'company',
      'tags',
      'timeZone',
      'dnc',
      'notes',
    ],
  ];
  for (final c in contacts) {
    rows.add([
      c.firstName,
      c.lastName,
      c.primaryPhone ?? '',
      c.emails.isEmpty ? '' : c.emails.first,
      c.companyId ?? '',
      c.tags.join('|'),
      c.timeZone ?? '',
      c.dnc ? '1' : '0',
      c.notes,
    ]);
  }
  return const ListToCsvConverter().convert(rows);
}

CsvImportResult contactsFromCsv(
  String csvText,
  List<Contact> existing,
  String Function() idGen,
) {
  final errors = <String>[];
  final imported = <Contact>[];
  var skipped = 0;
  final rows = const CsvToListConverter(
    shouldParseNumbers: false,
  ).convert(csvText, eol: '\n');
  if (rows.isEmpty) return CsvImportResult(const [], ['empty file'], 0);

  final header =
      rows.first.map((h) => h.toString().trim().toLowerCase()).toList();
  int col(String name) => header.indexOf(name);
  final fi = col('firstname');
  final li = col('lastname');
  final pi = col('phone');
  if (fi < 0 || li < 0) {
    return CsvImportResult(const [], [
      'missing required columns firstName/lastName',
    ], 0);
  }

  final existingKeys = existing.map(dedupeKey).toSet();
  final now = DateTime.now();
  for (var i = 1; i < rows.length; i++) {
    final r = rows[i];
    String cell(int idx) =>
        (idx >= 0 && idx < r.length) ? r[idx].toString().trim() : '';
    final first = cell(fi);
    final last = cell(li);
    if (first.isEmpty && last.isEmpty) continue;
    String? phone;
    final rawPhone = cell(pi);
    if (rawPhone.isNotEmpty) {
      phone = PhoneNumberUtil.normalize(rawPhone);
      if (phone == null) {
        errors.add('row ${i + 1}: invalid phone "$rawPhone"');
        continue;
      }
    }
    final contact = Contact(
      id: idGen(),
      firstName: first,
      lastName: last,
      phones:
          phone == null ? const [] : [PhoneEntry(label: 'mobile', e164: phone)],
      emails: cell(col('email')).isEmpty ? const [] : [cell(col('email'))],
      tags: cell(col('tags')).isEmpty ? const [] : cell(col('tags')).split('|'),
      timeZone: cell(col('timezone')).isEmpty ? null : cell(col('timezone')),
      dnc: cell(col('dnc')) == '1',
      notes: cell(col('notes')),
      createdAt: now,
      updatedAt: now,
    );
    final key = dedupeKey(contact);
    if (existingKeys.contains(key)) {
      skipped++;
      continue;
    }
    existingKeys.add(key);
    imported.add(contact);
  }
  return CsvImportResult(imported, errors, skipped);
}

/// Strongest available identifier: phone if present, else name.
String dedupeKey(Contact c) =>
    c.primaryPhone ??
    '${c.firstName.toLowerCase()}|${c.lastName.toLowerCase()}';

/// Finds duplicate groups among existing contacts (same dedupe key).
List<List<Contact>> findDuplicates(List<Contact> contacts) {
  final byKey = <String, List<Contact>>{};
  for (final c in contacts.where((c) => !c.archived)) {
    byKey.putIfAbsent(dedupeKey(c), () => []).add(c);
  }
  return byKey.values.where((g) => g.length > 1).toList();
}

/// Merges duplicates into the first contact, unioning phones/emails/tags.
Contact mergeContacts(List<Contact> group) {
  final base = group.first;
  final phones = <String, PhoneEntry>{};
  final emails = <String>{};
  final tags = <String>{};
  var notes = '';
  for (final c in group) {
    for (final p in c.phones) {
      phones[p.e164] = p;
    }
    emails.addAll(c.emails);
    tags.addAll(c.tags);
    if (c.notes.isNotEmpty) {
      notes = notes.isEmpty ? c.notes : '$notes\n${c.notes}';
    }
  }
  return base.copyWith(
    phones: phones.values.toList(),
    emails: emails.toList(),
    tags: tags.toList(),
    notes: notes,
    dnc: group.any((c) => c.dnc),
  );
}
