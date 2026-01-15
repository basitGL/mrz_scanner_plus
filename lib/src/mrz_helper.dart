import 'package:flutter/material.dart';
import 'package:mrz_scanner_plus/src/mrz_parser/mrz_parser.dart';
import 'package:mrz_scanner_plus/src/mrz_parser/mrz_result.dart';
import 'package:mrz_scanner_plus/src/mrz_postprocess.dart';

class MRZHelper {
  static var supportedDocTypes = <String>['A', 'C', 'P', 'V', 'I'];
  static List<String>? getFinalListToParse(List<String> ableToScanTextList) {
    if (ableToScanTextList.length < 2) {
      // minimum length of any MRZ format is 2 lines
      return null;
    }
    var lineLength = ableToScanTextList.first.length;
    for (final e in ableToScanTextList) {
      if (e.length != lineLength) {
        return null;
      }
      // to make sure that all lines are the same in length
    }
    var firstLineChars = ableToScanTextList.first.split('');

    var fChar = firstLineChars[0];
    if (supportedDocTypes.contains(fChar)) {
      return [...ableToScanTextList];
    }
    return null;
  }

  static String testTextLine(String text) {
    //sometimes the symbol is very same,cause cannot recognize the correct mrz code
    if (text.contains('<')) {
      text = text
          .replaceAll(' ', '')
          .replaceAll('‹', '<')
          .replaceAll('≪', '<')
          .replaceAll('⪡', '<')
          .replaceAll('«', '<')
          .replaceAll('⟨', '<')
          .replaceAll('<*', '<<')
          .replaceAll('《', '<')
          .replaceAll('‹', '<')
          .replaceAll('<K<', '<<<')
          .replaceAll('<k<', '<<<');
      final index = text.indexOf('<<<');
      if (index > 0) {
        final header = text.substring(0, index);
        var tail = text.substring(index, text.length);
        text = '$header${tail.replaceAll('k', '<').replaceAll('K', '<')}';
      }

      text = _ifNotEnough(text);
    }
    var list = text.split('');
    // to check if the text belongs to any MRZ format or not

    if (list.length != 44 && list.length != 30 && list.length != 36) {
      return (text.contains('<') && text.replaceAll('<', '').trim().isNotEmpty)
          ? text
          : '';
    }

    for (var i = 0; i < list.length; i++) {
      if (RegExp(r'^[A-Za-z0-9_.]+$').hasMatch(list[i])) {
        list[i] = list[i].toUpperCase();
        if (list[i] == 'l') list[i] = 'I';
        // to ensure that every letter is uppercase
      }
      if (double.tryParse(list[i]) == null &&
          !RegExp(r'^[A-Za-z0-9_.]+$').hasMatch(list[i])) {
        list[i] = '<';
        // sometimes < sign not recognized well
      }
    }
    var result = list.join();
    if (result.length == 44 && supportedDocTypes.contains(result[0])) {
      result = _fixTd3NameZone(result);
    }
    return result;
  }

  static MRZResult? parse(String recognizedText) {
    final lines = getMrzLines(recognizedText);
    if (lines == null) return null;
    return MRZParser.parse(lines);
  }

  static List<String>? getMrzLines(String recognizedText) {
    var fullText = recognizedText.trim().replaceAll(' ', '');
    List allText = fullText.split('\n');

    var ableToScanText = <String>[];
    for (final line in allText) {
      if (MRZHelper.testTextLine(line).isNotEmpty) {
        ableToScanText.add(MRZHelper.testTextLine(line));
      }
    }

    final mrzLines = _filterAvailableLines(ableToScanText);
    for (final mrz2Line in mrzLines) {
      debugPrint('OCR:\N${mrz2Line.join('\n')}');
      var lines = MRZHelper.getFinalListToParse(mrz2Line);
      if (lines != null && lines.isNotEmpty) {
        try {
          final sanitized = <String>[
            MrzPostprocess.sanitize(lines[0], forceLen: lines[0].length),
            if (lines.length > 1)
              MrzPostprocess.sanitize(lines[1], forceLen: lines[1].length),
          ];
          return sanitized;
        } catch (e) {
          debugPrint(e.toString());
        }
      }
    }
    return null;
  }

  static List<List<String>> _filterAvailableLines(List<String> lines) {
    final availableLines = <List<String>>[];
    final mrz44Lines = <String>[];

    var containSpecialSymbolLine = '<';

    for (final line in lines) {
      final length = line.length;
      if (length == 44) {
        mrz44Lines.add(line);
        continue;
      }

      if (line.contains('<')) {
        final isEmpty = line.replaceAll('<', '').trim().isEmpty;
        if (!isEmpty) {
          containSpecialSymbolLine = line;
        }
      }
    }

    if (mrz44Lines.isNotEmpty && mrz44Lines.length == 1) {
      mrz44Lines.insert(0,
          '$containSpecialSymbolLine${'<' * (44 - containSpecialSymbolLine.length)}');
    }

    if (mrz44Lines.length >= 2) availableLines.add(mrz44Lines);

    return availableLines;
  }

  static String _fixTd3NameZone(String line) {
    // TD3: 44 chars. Line 1 layout:
    // [0..1]=doc code, [2..4]=issuing state, [5..43]=names
    if (line.length != 44) return line;
    if (line.length < 6) return line;

    const nameStart = 5;
    final head = line.substring(0, nameStart);
    var zone = line.substring(nameStart);

    // Normalize common chevron lookalikes to '<'
    zone = zone.replaceAll(RegExp(r'[‹≪⪡«⟨《]'), '<');

    // Replace 'K/k' used as filler between chevrons: "<K<" or "<k<" or "<KK<"
    zone = zone.replaceAll(RegExp(r'(?<=<)[Kk]+(?=<)'), '');

    // Also handle cases like "K<" or "<K" at boundaries inside the zone
    // by removing leading/trailing K runs from name tokens.
    int sepIdx = zone.indexOf('<<');
    if (sepIdx < 0) {
      // If OCR collapsed '<<' into something else, we still try token-level cleanup.
      final tokens = zone.split('<').map(_trimKToken).toList();
      zone = tokens.join('<');
    } else {
      final surnameRaw = zone.substring(0, sepIdx);
      final givenRaw = zone.substring(sepIdx + 2);

      final surnameTokens = surnameRaw.split('<').map(_trimKToken).toList();
      final givenTokens = givenRaw.split('<').map(_trimKToken).toList();

      final surnameClean = surnameTokens.join('<');
      final givenClean = givenTokens.join('<');

      zone = '$surnameClean<<$givenClean';
    }

    // Ensure only valid MRZ charset in zone (A-Z, 0-9, <)
    zone = zone.replaceAll(RegExp(r'[^A-Z0-9<]'), '<');

    // Force zone length back to 39 (44 - 5) by padding/truncating with '<'
    const zoneLen = 39;
    if (zone.length > zoneLen) zone = zone.substring(0, zoneLen);
    if (zone.length < zoneLen) zone = zone.padRight(zoneLen, '<');

    return head + zone;
  }

  static String _trimKToken(String t) {
    if (t.isEmpty) return t;

    // Remove spurious K/k only when it looks like an OCR artifact at token edges.
    // We avoid deleting legitimate 'K' inside names like "KARIM".
    var s = t;

    // Leading K-run is suspicious if token length >= 2 and the rest is letters/digits
    if (s.length >= 2) {
      s = s.replaceFirst(RegExp(r'^[Kk]+(?=[A-Z0-9])'), '');
      s = s.replaceFirst(RegExp(r'(?<=[A-Z0-9])[Kk]+$'), '');
    }

    return s;
  }

  static String _ifNotEnough(String text) {
    if (text.length > 36 && text.length < 44) {
      return _createEnoughText(44, text);
    }
    return text;
  }

  static String _createEnoughText(int length, String text) {
    var leftLength = length - text.length;
    final index = text.indexOf('<');
    final header = text.substring(0, index);
    final tail = text.substring(index, text.length);
    return '$header${'<' * leftLength}$tail';
  }
}
