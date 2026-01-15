import 'dart:io';
import 'dart:ui' as ui;
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:mrz_scanner_plus/mrz_scanner_plus.dart';
import 'package:mrz_scanner_plus/src/parser.dart';
import 'package:mrz_scanner_plus/src/services/image_correctness_checker.dart';
import 'dart:developer' as dev;

typedef OnMRZDetected = void Function(
  List<String>? mrzLines,
  RecognizedText recognizedText,
  MRZResult mrzResult,
);
typedef OnDetected = void Function(String recognizeText);
typedef OnPhotoTaken = void Function(String imagePath);

class MrzCameraController {
  CameraController? controller;
  BuildContext? context;

  void _bind(CameraController? controller, BuildContext context) {
    this.controller = controller;
    this.context = context;
  }

  void takePicture() {
    final state = context?.findAncestorStateOfType<_CameraViewState>();
    state?._takePicture();
  }
}

enum CameraMode { scan, photo }

class CameraView extends StatefulWidget {
  final Color? indicatorColor;
  final OnMRZDetected? onMRZDetected;
  final OnPhotoTaken? onPhotoTaken;
  final OnDetected? onDetected;
  final VoidCallback? onImageBlurry;
  final Widget? customOverlay;
  final CameraMode mode;
  final MrzCameraController? controller;
  final Widget? photoButton;
  final TextRecognitionScript script;

  const CameraView({
    super.key,
    this.controller,
    this.indicatorColor,
    this.onMRZDetected,
    this.onDetected,
    this.onPhotoTaken,
    this.customOverlay,
    this.mode = CameraMode.scan,
    this.photoButton,
    this.script = TextRecognitionScript.latin,
    this.onImageBlurry,
  });

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView>
    with SingleTickerProviderStateMixin {
  CameraController? _controller;
  late TextRecognizer _textRecognizer;
  final checker = const ImageCorrectnessChecker();

  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _textRecognizer = TextRecognizer(script: widget.script);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();
    if (cameras.isEmpty) return;

    final camera = cameras.first;
    _controller = CameraController(
      camera,
      ResolutionPreset.max,
      enableAudio: false,
    );

    await _controller?.initialize();

    if (!mounted) return;
    setState(() {});
    widget.controller?._bind(_controller, context);

    if (widget.mode == CameraMode.scan) {
      await _controller?.setFocusMode(FocusMode.auto);
      Future.delayed(const Duration(seconds: 3), () async {
        if (!mounted ||
            _controller == null ||
            !_controller!.value.isInitialized) {
          return;
        }
        await _startImageStream();
      });
    }

    // await _controller?.initialize();
    // if (widget.mode == CameraMode.scan) {
    //   await _controller?.setFocusMode(FocusMode.auto);
    //   await Future.delayed(const Duration(seconds: 2));
    //   await _startImageStream();
    // }
    // if (mounted) setState(() {});
    // widget.controller?._bind(_controller, context);
  }

  bool _isProcessing = false;
  DateTime _lastProcessTime = DateTime.now();

  Future<void> _startImageStream() async {
    _controller?.startImageStream((CameraImage image) async {
      final now = DateTime.now();
      if (_isProcessing ||
          now.difference(_lastProcessTime).inMilliseconds < 1000) {
        return;
      }
      _isProcessing = true;
      _lastProcessTime = now;

      try {
        final InputImage inputImage = _processImageForMlKit(image);
        final blurry = checker.isImageBlurry(image);
        if (blurry) {
          if (widget.mode == CameraMode.scan && widget.onImageBlurry != null) {
            widget.onImageBlurry!();
          }
          return;
        }
        final recognizedText = await _textRecognizer.processImage(inputImage);
        widget.onDetected?.call(recognizedText.text);
        final mrzResult = Parser.parse(recognizedText.text);
        if (mrzResult == null || widget.onMRZDetected == null) return;
        if (mrzResult.isUnAvailable()) return;

        if (_controller != null && _controller!.value.isInitialized) {
          _controller?.stopImageStream();
          // final cropFile = await _takeAndCropImage();
          final mrzLines = MRZHelper.getMrzLines(recognizedText.text);
          dev.log(mrzLines.toString(), name: 'MRZ Lines:');
          dev.log(recognizedText.text, name: 'Recognized Text:');
          Future.delayed(const Duration(milliseconds: 500), () {
            widget.onMRZDetected?.call(
              mrzLines,
              recognizedText,
              mrzResult,
            );
          });
        }
      } catch (e) {
        debugPrint(e.toString());
      } finally {
        _isProcessing = false;
      }
    });
  }

  InputImage _processImageForMlKit(CameraImage image) {
    final rotation = _getInputImageRotation();

    final imageSize = Size(image.width.toDouble(), image.height.toDouble());

    if (Platform.isAndroid) {
      // Most Android devices deliver YUV_420_888 with 3 planes for CameraImage.
      // Convert to NV21 and pass consistent metadata.
      final Uint8List bytes;
      final InputImageFormat format;
      final int bytesPerRow;

      if (image.planes.length == 3) {
        bytes = _yuv420ToNv21(image);
        format = InputImageFormat.nv21;
        bytesPerRow = image.width; // For NV21, row stride is width
      } else if (image.planes.length == 1) {
        // Some devices may give NV21-like single plane; treat carefully.
        // If it's truly NV21, you can pass it directly.
        bytes = image.planes[0].bytes;
        format = InputImageFormat.nv21;
        bytesPerRow = image.planes[0].bytesPerRow;
      } else {
        // Fallback: concatenate planes (least reliable); better to throw/log.
        final WriteBuffer allBytes = WriteBuffer();
        for (final plane in image.planes) {
          allBytes.putUint8List(plane.bytes);
        }
        bytes = allBytes.done().buffer.asUint8List();
        // Still declare yuv_420_888 if you do this fallback
        format = InputImageFormat.yuv_420_888;
        bytesPerRow = image.planes.first.bytesPerRow;
      }

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: rotation,
          format: format,
          bytesPerRow: bytesPerRow,
        ),
      );
    }

    // iOS: typically BGRA8888 (single plane). Your original path is fine,
    // but do not hardcode rotation if you allow device rotation.
    final bytes = image.planes[0].bytes;

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: imageSize,
        rotation: rotation,
        format: InputImageFormat.bgra8888,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  @override
  void dispose() {
    if (_controller?.value.isStreamingImages ?? false) {
      _controller?.stopImageStream();
    }
    _controller?.dispose();
    _textRecognizer.close();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _takePicture() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final file = await _takeAndCropImage();
    widget.onPhotoTaken?.call(file.path);
  }

  @override
  Widget build(BuildContext context) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final frame = mrzFrameRect(size);
        return Stack(
          fit: StackFit.expand,
          children: [
            SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: _controller!.value.previewSize!.height,
                  height: _controller!.value.previewSize!.width,
                  child: CameraPreview(_controller!),
                ),
              ),
            ),
            if (widget.customOverlay != null)
              widget.customOverlay!
            else if (widget.mode == CameraMode.scan)
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _animationController,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: MaskPainter(
                        animationValue: _animationController.value,
                        indicatorColor:
                            widget.indicatorColor ?? const Color(0xFFE1DED7),
                      ),
                      size: Size.infinite,
                      child: const SizedBox.expand(),
                    );
                  },
                ),
              )
            else
              CustomPaint(
                painter: MaskPainter(
                  animationValue: null,
                  indicatorColor:
                      widget.indicatorColor ?? const Color(0xFFE1DED7),
                ),
                size: Size.infinite,
                child: const SizedBox.expand(),
              ),
            Positioned(
              left: 0,
              right: 0,
              top: frame.bottom + 16,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 22),
                child: Text(
                  "Position the front of your passport \nin the frame",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (widget.mode == CameraMode.photo)
              widget.photoButton ?? _photoWidget(),
          ],
        );
      },
    );
  }

  Widget _photoWidget() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 60,
      child: Container(
        width: 100,
        height: 100,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              width: 3,
              color: widget.indicatorColor ?? const Color(0xFFE1DED7)),
        ),
        child: Container(
          width: 85,
          height: 85,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _takePicture,
            ),
          ),
        ),
      ),
    );
  }

  InputImageRotation _getInputImageRotation() {
    final controller = _controller;
    if (controller == null) return InputImageRotation.rotation0deg;

    final sensorOrientation = controller.description.sensorOrientation;

    // This is the *preview* / device orientation as reported by the camera plugin.
    // It updates as device rotates (unless you lock orientation).
    final deviceOrientation = controller.value.deviceOrientation;

    // Map DeviceOrientation -> degrees
    int deviceRotationDegrees;
    switch (deviceOrientation) {
      case DeviceOrientation.portraitUp:
        deviceRotationDegrees = 0;
        break;
      case DeviceOrientation.landscapeLeft:
        deviceRotationDegrees = 90;
        break;
      case DeviceOrientation.portraitDown:
        deviceRotationDegrees = 180;
        break;
      case DeviceOrientation.landscapeRight:
        deviceRotationDegrees = 270;
        break;
    }

    // For back camera, rotation is typically (sensor - device + 360) % 360
    // For front camera, it's (sensor + device) % 360 (mirroring differences).
    final isFrontCamera =
        controller.description.lensDirection == CameraLensDirection.front;

    final rotationDegrees = isFrontCamera
        ? (sensorOrientation + deviceRotationDegrees) % 360
        : (sensorOrientation - deviceRotationDegrees + 360) % 360;

    switch (rotationDegrees) {
      case 0:
        return InputImageRotation.rotation0deg;
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        // Fallback if something unexpected happens
        return InputImageRotation.rotation0deg;
    }
  }

  Future<File> _takeAndCropImage() async {
    final XFile picture = await _controller!.takePicture();
    // 处理图片旋转
    final imageFile = File(picture.path);

    final bytes = await imageFile.readAsBytes();
    final image = await decodeImageFromList(bytes);

    // 获取预览尺寸和实际图片尺寸
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    final screenRatio = screenWidth / screenHeight;
    final realWidth = image.height * screenRatio;

    final bool isPortrait = image.height > image.width;

    // 计算护照尺寸（与遮罩框相同的比例1.42:1）
    final double cardWidth = realWidth /** 0.85*/;
    final double cardHeight = cardWidth / 1.42;
    final double left = (image.width - cardWidth) / 2;
    final double top = (image.height - cardHeight) / 2;

    // 创建护照尺寸的裁剪区域
    final ui.Rect cropRect = ui.Rect.fromLTWH(
      left,
      top,
      cardWidth,
      cardHeight,
    );

    // 创建PictureRecorder和Canvas
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);

    if (isPortrait) {
      // 竖屏模式，不需要旋转
      canvas.drawImageRect(
        image,
        cropRect, // 源矩形使用裁剪区域
        Rect.fromLTWH(0, 0, cardWidth, cardHeight), // 目标矩形使用裁剪尺寸
        Paint(),
      );
    } else {
      // 横屏模式，需要旋转90度
      canvas.translate(cardHeight, 0);
      canvas.rotate(pi / 2);
      canvas.drawImageRect(
        image,
        cropRect, // 源矩形使用裁剪区域
        Rect.fromLTWH(0, 0, cardWidth, cardHeight), // 目标矩形使用裁剪尺寸
        Paint(),
      );
    }

    // 获取处理后的图像
    final ui.Picture imagePicture = recorder.endRecording();
    final ui.Image processedImage = await imagePicture.toImage(
      cardWidth.round(),
      cardHeight.round(),
    );
    // 转换为字节数据
    final ByteData? byteData =
        await processedImage.toByteData(format: ui.ImageByteFormat.png);
    final Uint8List processedBytes = byteData!.buffer.asUint8List();
    await imageFile.writeAsBytes(processedBytes);

    // 释放资源
    image.dispose();
    processedImage.dispose();
    return imageFile;
  }

  Rect mrzFrameRect(Size size) {
    final cardWidth = size.width * 0.85;
    final cardHeight = cardWidth / 1.42;
    final left = (size.width - cardWidth) / 2;
    final top = (size.height - cardHeight) / 2;
    return Rect.fromLTWH(left, top, cardWidth, cardHeight);
  }
}

Uint8List _yuv420ToNv21(CameraImage image) {
  final width = image.width;
  final height = image.height;

  final yPlane = image.planes[0];
  final uPlane = image.planes[1];
  final vPlane = image.planes[2];

  final yBytes = yPlane.bytes;
  final uBytes = uPlane.bytes;
  final vBytes = vPlane.bytes;

  final yRowStride = yPlane.bytesPerRow;

  final uvRowStride = uPlane.bytesPerRow;
  final uvPixelStride = uPlane.bytesPerPixel ?? 1;

  // NV21 = Y plane (W*H) + interleaved VU (W*H/2)
  final nv21 = Uint8List(width * height + (width * height ~/ 2));

  // Copy Y plane (respect row stride)
  int nv21Index = 0;
  for (int row = 0; row < height; row++) {
    final yRowStart = row * yRowStride;
    nv21.setRange(nv21Index, nv21Index + width, yBytes, yRowStart);
    nv21Index += width;
  }

  // Interleave V and U bytes (NV21 expects VU order)
  // UV planes are half resolution (height/2, width/2)
  final uvHeight = height ~/ 2;
  final uvWidth = width ~/ 2;

  for (int row = 0; row < uvHeight; row++) {
    final uvRowStart = row * uvRowStride;
    for (int col = 0; col < uvWidth; col++) {
      final uvIndex = uvRowStart + col * uvPixelStride;

      final v = vBytes[uvIndex];
      final u = uBytes[uvIndex];

      nv21[nv21Index++] = v;
      nv21[nv21Index++] = u;
    }
  }

  return nv21;
}
