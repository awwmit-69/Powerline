/// Phone-number normalization and formatting utilities.
///
/// ZIP-code-style discipline applies: numbers are strings, never ints, and
/// leading digits are always preserved.
library;

class PhoneNumberUtil {
  PhoneNumberUtil._();

  /// Normalizes raw user input to E.164 where possible.
  /// Returns null if the input cannot be a valid dialable number.
  static String? normalize(String raw, {String defaultCountry = 'US'}) {
    var s = raw.replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
    if (s.isEmpty) return null;
    if (s.startsWith('00')) s = '+${s.substring(2)}';
    if (s.startsWith('+')) {
      final digits = s.substring(1);
      if (!RegExp(r'^[1-9]\d{6,14}$').hasMatch(digits)) return null;
      return '+$digits';
    }
    if (!RegExp(r'^\d+$').hasMatch(s)) return null;
    if (defaultCountry == 'US') {
      if (s.length == 10) return '+1$s';
      if (s.length == 11 && s.startsWith('1')) return '+$s';
      return null;
    }
    return null;
  }

  /// Pretty-formats an E.164 US number as (XXX) XXX-XXXX; passes through others.
  static String format(String e164) {
    if (e164.startsWith('+1') && e164.length == 12) {
      final d = e164.substring(2);
      return '(${d.substring(0, 3)}) ${d.substring(3, 6)}-${d.substring(6)}';
    }
    return e164;
  }

  /// Progressive formatting while the user types on the dialpad.
  static String formatPartial(String digits) {
    final d = digits.replaceAll(RegExp(r'\D'), '');
    if (d.isEmpty) return '';
    if (d.length <= 3) return d;
    if (d.length <= 6) return '(${d.substring(0, 3)}) ${d.substring(3)}';
    if (d.length <= 10) {
      return '(${d.substring(0, 3)}) ${d.substring(3, 6)}-${d.substring(6)}';
    }
    return d;
  }

  static bool isValidE164(String s) => RegExp(r'^\+[1-9]\d{6,14}$').hasMatch(s);

  /// True when the number sits in a clearly-fictional demo range (555-01xx style).
  static bool isFictionalDemoNumber(String e164) =>
      RegExp(r'^\+1\d{3}55501\d{2}$').hasMatch(e164);
}
