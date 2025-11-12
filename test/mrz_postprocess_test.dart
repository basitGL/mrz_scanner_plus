import 'package:flutter_test/flutter_test.dart';
import 'package:mrz_scanner_plus/src/mrz_postprocess.dart';

void main() {
  test('Sanitize & keep length', () {
    const raw = 'p<utoDOE<<alI<<<'; // messy OCR, lowercase + small ell
    final l1 = MrzPostprocess.sanitize(raw, forceLen: 44);
    expect(l1.length, 44);
    expect(l1.contains('I'), true); // l → I normalized
  });
}
