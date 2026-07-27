import 'package:flutter_test/flutter_test.dart';
import 'package:powerline/core/util/csv_io.dart';
import 'package:powerline/domain/models/models.dart';

int _n = 0;
String idGen() => 'gen_${_n++}';

Contact c(String first, String last, {String? phone}) => Contact(
      id: 'x${_n++}',
      firstName: first,
      lastName: last,
      phones:
          phone == null ? const [] : [PhoneEntry(label: 'mobile', e164: phone)],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

void main() {
  test('CSV round-trip preserves phone as string', () {
    final contacts = [c('Avery', 'Abbott', phone: '+12145550100')];
    final csv = contactsToCsv(contacts);
    final result = contactsFromCsv(csv, const [], idGen);
    expect(result.imported.length, 1);
    expect(result.imported.first.primaryPhone, '+12145550100');
  });

  test('CSV import normalizes and skips duplicates', () {
    const csv =
        'firstName,lastName,phone\nJordan,Barlow,214 555 0105\nJordan,Barlow,2145550105\n';
    final result = contactsFromCsv(csv, const [], idGen);
    expect(result.imported.length, 1);
    expect(result.skippedDuplicates, 1);
    expect(result.imported.first.primaryPhone, '+12145550105');
  });

  test('CSV import reports invalid phone as error', () {
    const csv = 'firstName,lastName,phone\nRiley,Calder,not-a-number\n';
    final result = contactsFromCsv(csv, const [], idGen);
    expect(result.imported, isEmpty);
    expect(result.errors.single, contains('invalid phone'));
  });

  test('missing required columns reported', () {
    const csv = 'name,phone\nfoo,123\n';
    final result = contactsFromCsv(csv, const [], idGen);
    expect(result.errors.single, contains('missing required columns'));
  });

  test('duplicate detection groups by phone then name', () {
    final list = [
      c('Avery', 'Abbott', phone: '+12145550100'),
      c('Avery', 'Abbott', phone: '+12145550100'),
      c('Solo', 'Person'),
    ];
    final dupes = findDuplicates(list);
    expect(dupes.length, 1);
    expect(dupes.first.length, 2);
  });

  test('merge unions phones/emails/tags and DNC', () {
    final a = Contact(
      id: 'a',
      firstName: 'A',
      lastName: 'B',
      phones: const [PhoneEntry(label: 'mobile', e164: '+12145550100')],
      emails: const ['a@mail.example'],
      tags: const ['x'],
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final b = Contact(
      id: 'b',
      firstName: 'A',
      lastName: 'B',
      phones: const [PhoneEntry(label: 'work', e164: '+12145550200')],
      emails: const ['b@mail.example'],
      tags: const ['y'],
      dnc: true,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    final merged = mergeContacts([a, b]);
    expect(merged.phones.length, 2);
    expect(merged.emails.toSet(), {'a@mail.example', 'b@mail.example'});
    expect(merged.tags.toSet(), {'x', 'y'});
    expect(merged.dnc, isTrue);
  });
}
