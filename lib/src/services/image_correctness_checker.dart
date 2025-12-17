import 'package:camera/camera.dart';

class ImageCorrectnessChecker {
  final double blurThreshold;
  final int step;

  const ImageCorrectnessChecker({
    this.blurThreshold = 100.0,
    this.step = 3,
  });

  bool isImageBlurry(CameraImage image) {
    final variance = laplacianVariance(image);
    return variance < blurThreshold;
  }

  double laplacianVariance(CameraImage image) {
    if (image.planes.isEmpty) return 0;
    if (image.planes.length >= 3) {
      return _laplacianVarianceFromYPlane(image);
    } else {
      return _laplacianVarianceFromBGRA(image);
    }
  }

  double _laplacianVarianceFromYPlane(CameraImage image) {
    final width = image.width;
    final height = image.height;

    final yPlane = image.planes[0];
    final bytes = yPlane.bytes;
    final rowStride = yPlane.bytesPerRow;

    // Welford running variance for Laplacian values
    int count = 0;
    double mean = 0;
    double m2 = 0;

    // Sample inner pixels only
    for (int y = 1; y < height - 1; y += step) {
      final row = y * rowStride;
      final rowUp = (y - 1) * rowStride;
      final rowDown = (y + 1) * rowStride;

      for (int x = 1; x < width - 1; x += step) {
        final center = bytes[row + x];
        final top = bytes[rowUp + x];
        final bottom = bytes[rowDown + x];
        final left = bytes[row + x - 1];
        final right = bytes[row + x + 1];

        final laplacian = (center * 4) - top - bottom - left - right;

        count++;
        final delta = laplacian - mean;
        mean += delta / count;
        final delta2 = laplacian - mean;
        m2 += delta * delta2;
      }
    }

    if (count < 2) return 0;
    return m2 / count; // population variance
  }

  double _laplacianVarianceFromBGRA(CameraImage image) {
    final width = image.width;
    final height = image.height;

    final plane = image.planes[0];
    final bytes = plane.bytes;
    final rowStride = plane.bytesPerRow;
    final bytesPerPixel = plane.bytesPerPixel ?? 4; // typically 4 for BGRA

    int count = 0;
    double mean = 0;
    double m2 = 0;

    int luminanceAt(int x, int y) {
      final index = y * rowStride + x * bytesPerPixel;
      // BGRA order
      final b = bytes[index + 0];
      final g = bytes[index + 1];
      final r = bytes[index + 2];

      // Integer approximation of Rec. 601 luma:
      // Y ≈ 0.299R + 0.587G + 0.114B
      return ((77 * r + 150 * g + 29 * b) >> 8);
    }

    for (int y = 1; y < height - 1; y += step) {
      for (int x = 1; x < width - 1; x += step) {
        final center = luminanceAt(x, y);
        final top = luminanceAt(x, y - 1);
        final bottom = luminanceAt(x, y + 1);
        final left = luminanceAt(x - 1, y);
        final right = luminanceAt(x + 1, y);

        final laplacian = (center * 4) - top - bottom - left - right;

        count++;
        final delta = laplacian - mean;
        mean += delta / count;
        final delta2 = laplacian - mean;
        m2 += delta * delta2;
      }
    }

    if (count < 2) return 0;
    return m2 / count;
  }
}
