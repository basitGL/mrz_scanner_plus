import 'package:characters/characters.dart';

/// Minimal MRZ sanitizer + name parser (TD3 passports, 44-char lines).
/// Works as a post-process step on raw OCR lines before your existing parser.
class MrzPostprocess {
  static final _illegal = RegExp(r'[^A-Z0-9<]');

  // Common OCR confusions. Keep conservative for the name line.
  static const Map<String, String> _confusion = {
    'l': 'I', 'i': 'I',
    'o': 'O',
    'b': 'B',
    's': 'S',
    // digits/bar
    '|': '1',
  };

  /// Sanitize raw OCR output into MRZ-safe string.
  /// Set [forceLen] to 44 for TD3 lines.
  static String sanitize(String raw, {int? forceLen}) {
    var s = raw.trim();

    // Map common confusions + uppercase.
    final buf = StringBuffer();
    for (final ch in s.characters) {
      final mapped = _confusion[ch] ?? ch.toUpperCase();
      buf.write(mapped);
    }
    s = buf.toString();

    // Replace spaces and illegal chars with '<'
    s = s.replaceAll(' ', '<');
    s = s.replaceAll(_illegal, '<');

    if (forceLen != null) {
      if (s.length > forceLen) s = s.substring(0, forceLen);
      if (s.length < forceLen) s = s.padRight(forceLen, '<');
    }
    return s;
  }

  /// Parse surname and given names from TD3 line 1.
  /// Example: P<UTOERIKSSON<<ANNA<MARIA<<<
  static ({String surname, String givenNames}) parseNamesFromLine1(
      String line1) {
    // TD3: positions 0-1 doc code, 2-4 issuing state, names from index 5.
    final namesField = line1.length >= 6 ? line1.substring(5) : '';
    final parts = namesField.split('<<');
    final rawSurname = parts.isNotEmpty ? parts.first : '';
    final rawGiven = parts.length > 1 ? parts.sublist(1).join(' ') : '';

    String toHuman(String mrz) =>
        mrz.replaceAll('<', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    return (surname: toHuman(rawSurname), givenNames: toHuman(rawGiven));
  }

  /// MRZ check digit for numeric/date fields. Useful if you later add
  /// repair logic for doc number / DOB / expiry.
  static String checkDigit(String field) {
    const weights = [7, 3, 1];
    const alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ<';
    int cv(String c) => alphabet.indexOf(c).clamp(0, alphabet.length - 1);
    var sum = 0;
    for (var i = 0; i < field.length; i++) {
      sum += cv(field[i]) * weights[i % 3];
    }
    return (sum % 10).toString();
  }
}
