import 'dart:io' show File;
import 'dart:math' show pow;
import 'package:image/image.dart' as img;

class ImageCorrectnessChecker {
  bool isImageBlurry(File imageFile) {
    final variance = _calculateLaplacianVariance(imageFile);
    const blurThreshold = 100.0;

    if (variance < blurThreshold) {
      return true;
    }
    return false;
  }

  double _calculateLaplacianVariance(File file) {
    final bytes = file.readAsBytesSync();
    final image = img.decodeImage(bytes)!;
    final gray = img.grayscale(image);

    final width = gray.width;
    final height = gray.height;

    final laplacianValues = <int>[];

    for (int y = 1; y < height - 1; y++) {
      for (int x = 1; x < width - 1; x++) {
        final center = img.getLuminance(gray.getPixel(x, y));
        final top = img.getLuminance(gray.getPixel(x, y - 1));
        final bottom = img.getLuminance(gray.getPixel(x, y + 1));
        final left = img.getLuminance(gray.getPixel(x - 1, y));
        final right = img.getLuminance(gray.getPixel(x + 1, y));

        final laplacian = center * 4 - top - bottom - left - right;

        laplacianValues.add(laplacian.toInt());
      }
    }

    final mean =
        laplacianValues.reduce((a, b) => a + b) / laplacianValues.length;

    final variance =
        laplacianValues.map((v) => pow(v - mean, 2)).reduce((a, b) => a + b) /
            laplacianValues.length;

    return variance.toDouble();
  }
}
