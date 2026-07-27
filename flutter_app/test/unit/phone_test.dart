import 'package:flutter_test/flutter_test.dart';
import 'package:powerline/core/util/phone.dart';

void main() {
  group('PhoneNumberUtil.normalize', () {
    test('normalizes 10-digit US number', () {
      expect(PhoneNumberUtil.normalize('214 555 0100'), '+12145550100');
    });
    test('normalizes 11-digit with leading 1', () {
      expect(PhoneNumberUtil.normalize('1-314-555-0101'), '+13145550101');
    });
    test('keeps E.164 input', () {
      expect(PhoneNumberUtil.normalize('+18885550103'), '+18885550103');
    });
    test('converts 00 international prefix', () {
      expect(PhoneNumberUtil.normalize('0044201234567'), '+44201234567');
    });
    test('rejects junk', () {
      expect(PhoneNumberUtil.normalize('hello'), isNull);
      expect(PhoneNumberUtil.normalize('12'), isNull);
    });
    test('preserves leading digits (no int coercion)', () {
      expect(PhoneNumberUtil.normalize('2145550100'), '+12145550100');
    });
  });

  group('formatting', () {
    test('formats US E.164', () {
      expect(PhoneNumberUtil.format('+12145550100'), '(214) 555-0100');
    });
    test('partial formatting while typing', () {
      expect(PhoneNumberUtil.formatPartial('21455'), '(214) 55');
      expect(PhoneNumberUtil.formatPartial('2145550100'), '(214) 555-0100');
    });
    test('recognizes fictional demo range', () {
      expect(PhoneNumberUtil.isFictionalDemoNumber('+12145550100'), isTrue);
      expect(PhoneNumberUtil.isFictionalDemoNumber('+12145551234'), isFalse);
    });
  });
}
