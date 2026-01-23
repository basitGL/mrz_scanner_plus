part of 'mrz_parser.dart';

class _TD3MRZFormatParser {
  _TD3MRZFormatParser._();

  static const _linesLength = 44;
  static const _linesCount = 2;

  static bool isValidInput(List<String> input) =>
      input.length == _linesCount &&
      input.every((s) => s.length == _linesLength);

  static MRZResult parse(List<String> input) {
    if (!isValidInput(input)) {
      throw const InvalidMRZInputException();
    }

    final firstLine = input[0];
    final secondLine = input[1];

    log("formatter-firstLine: $firstLine");
    log("formatter-secondLine: $secondLine");

    final documentTypeRaw = firstLine.substring(0, 2);
    final countryCodeRaw = firstLine.substring(2, 5);
    final namesRaw = firstLine.substring(5);
    final documentNumberRaw = secondLine.substring(0, 9);
    final documentNumberCheckDigitRaw = secondLine[9];
    final nationalityRaw = secondLine.substring(10, 13);
    final birthDateRaw = secondLine.substring(13, 19);
    final birthDateCheckDigitRaw = secondLine[19];
    final sexRaw = secondLine.substring(20, 21);
    final expiryDateRaw = secondLine.substring(21, 27);
    final expiryDateCheckDigitRaw = secondLine[27];
    final optionalDataRaw = secondLine.substring(28, 42);
    final optionalDataCheckDigitRaw = secondLine[42];
    final finalCheckDigitRaw = secondLine.substring(43);

    final documentTypeFixed =
        MRZFieldRecognitionDefectsFixer.fixDocumentType(documentTypeRaw);
    final countryCodeFixed =
        MRZFieldRecognitionDefectsFixer.fixCountryCode(countryCodeRaw);
    final namesFixed = MRZFieldRecognitionDefectsFixer.fixNames(namesRaw);
    final documentNumberFixed = documentNumberRaw;
    // final documentNumberCheckDigitFixed =
    //     MRZFieldRecognitionDefectsFixer.fixCheckDigit(
    //   documentNumberCheckDigitRaw,
    // );
    final nationalityFixed =
        MRZFieldRecognitionDefectsFixer.fixNationality(nationalityRaw);
    final birthDateFixed =
        MRZFieldRecognitionDefectsFixer.fixDate(birthDateRaw);
    final birthDateCheckDigitFixed =
        MRZFieldRecognitionDefectsFixer.fixCheckDigit(birthDateCheckDigitRaw);
    final sexFixed = MRZFieldRecognitionDefectsFixer.fixSex(sexRaw);
    final expiryDateFixed =
        MRZFieldRecognitionDefectsFixer.fixDate(expiryDateRaw);
    final expiryDateCheckDigitFixed =
        MRZFieldRecognitionDefectsFixer.fixCheckDigit(expiryDateCheckDigitRaw);
    final optionalDataFixed = optionalDataRaw;

    final birthDateIsValid = int.tryParse(birthDateCheckDigitFixed) ==
        MRZCheckDigitCalculator.getCheckDigit(birthDateFixed);

    if (!birthDateIsValid) {
      throw const InvalidBirthDateException();
    }

    final expiryDateIsValid = int.tryParse(expiryDateCheckDigitFixed) ==
        MRZCheckDigitCalculator.getCheckDigit(expiryDateFixed);

    if (!expiryDateIsValid) {
      throw const InvalidExpiryDateException();
    }

    final documentType = MRZFieldParser.parseDocumentType(documentTypeFixed);
    final countryCode = MRZFieldParser.parseCountryCode(countryCodeFixed);
    final names = MRZFieldParser.parseNames(namesFixed);
    final documentNumber =
        MRZFieldParser.parseDocumentNumber(documentNumberFixed);
    final nationality = MRZFieldParser.parseNationality(nationalityFixed);
    final birthDate = MRZFieldParser.parseBirthDate(birthDateFixed);
    final sex = MRZFieldParser.parseSex(sexFixed);
    final expiryDate = MRZFieldParser.parseExpiryDate(expiryDateFixed);
    final optionalData = MRZFieldParser.parseOptionalData(optionalDataFixed);

    log("formatter-name-fix:: $namesFixed");
    log("formatter-raw-name:: $namesRaw");

    log("td3 values: ");
    log("documentType: $documentType");
    log("countryCode: $countryCode");
    log("names: $names");
    log("documentNumber: $documentNumber");
    log("nationality: $nationality");
    log("birthDate: $birthDate");
    log("sex: $sex");
    log("expiryDate: $expiryDate");
    log("optionalData: $optionalData");

    final result = MRZResult(
      documentType: documentType,
      countryCode: countryCode,
      surnames: names[0],
      givenNames: names[1],
      documentNumber: documentNumber,
      nationalityCountryCode: nationality,
      birthDate: birthDate,
      sex: sex,
      expiryDate: expiryDate,
      personalNumber: optionalData,
    );
    log("result td3:");
    log(result.toString());
    return result;
  }
}
