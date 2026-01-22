part of 'mrz_parser.dart';

class MRZFieldRecognitionDefectsFixer {
  MRZFieldRecognitionDefectsFixer._();

  static String fixDocumentType(String input) =>
      input.replaceSimilarDigitsWithLetters();

  static String fixCheckDigit(String input) =>
      input.replaceSimilarLettersWithDigits();

  static String fixDate(String input) =>
      input.replaceSimilarLettersWithDigits();

  static String fixSex(String input) => input.replaceAll('P', 'F');

  static String fixCountryCode(String input) =>
      input.replaceSimilarDigitsWithLetters();

  // static String fixNames(String input) =>
  //     input.replaceSimilarDigitsWithLetters();
  static String fixNames(String input) {
    var s = input.toUpperCase();

    // normalize known chevron lookalikes
    s = s.replaceAll(RegExp(r'[‹≪⪡«⟨《]'), '<');

    // remove K/k used as filler between chevrons: "<K<" or "<KK<"
    // s = s.replaceAll(RegExp(r'(?<=<)[K]+(?=<)'), '');

    // cleanup token-edge K only in the names field (conservative)
    final parts = s.split('<').map((p) {
      if (p.length >= 2) {
        p = p.replaceFirst(RegExp(r'^K+(?=[A-Z])'), '');
        p = p.replaceFirst(RegExp(r'(?<=[A-Z])K+$'), '');
      }
      return p;
    }).toList();

    s = parts.join('<');

    // only allow A-Z and '<' in names (digits are almost always OCR noise here)
    s = s.replaceAll(RegExp(r'[^A-Z<]'), '<');

    return s;
  }

  static String fixNationality(String input) =>
      input.replaceSimilarDigitsWithLetters();
}
