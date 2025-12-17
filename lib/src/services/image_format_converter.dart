import 'dart:io';

import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart' show getTemporaryDirectory;

class ImageFormatConverter {
  Future<File> cameraImageToFile(CameraImage image) async {
    final converted = convertCameraImage(image);
    final jpeg = img.encodeJpg(converted, quality: 85);

    final dir = await getTemporaryDirectory();
    final file =
        File('${dir.path}/${DateTime.now().millisecondsSinceEpoch}.jpg');

    await file.writeAsBytes(jpeg);
    return file;
  }

  img.Image convertCameraImage(CameraImage cameraImage) {
    final width = cameraImage.width;
    final height = cameraImage.height;

    final imgImage = img.Image(width: width, height: height);

    final yPlane = cameraImage.planes[0];
    final uPlane = cameraImage.planes[1];
    final vPlane = cameraImage.planes[2];

    final yRowStride = yPlane.bytesPerRow;
    final uvRowStride = uPlane.bytesPerRow;
    final uvPixelStride = uPlane.bytesPerPixel!;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final yIndex = y * yRowStride + x;
        final uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;

        final yValue = yPlane.bytes[yIndex];
        final uValue = uPlane.bytes[uvIndex];
        final vValue = vPlane.bytes[uvIndex];

        final r = (yValue + 1.403 * (vValue - 128)).clamp(0, 255).toInt();
        final g = (yValue - 0.344 * (uValue - 128) - 0.714 * (vValue - 128))
            .clamp(0, 255)
            .toInt();
        final b = (yValue + 1.770 * (uValue - 128)).clamp(0, 255).toInt();

        imgImage.setPixelRgb(x, y, r, g, b);
      }
    }

    return imgImage;
  }
}
