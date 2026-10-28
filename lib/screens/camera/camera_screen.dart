import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;

import '../../models/answer_key.dart';
import '../../models/scan_result.dart';
import '../../services/omr_service.dart';
import '../../widgets/live_scan_overlay.dart';
import '../../widgets/document_scanner_animation.dart';
import '../../widgets/roll_number_dialog.dart';
import '../../omr/detection/class_9_10_detector.dart';
import '../../omr/detection/live_document_detector.dart';
import '../../omr/detection/sheet_detector.dart';
import '../../omr/detection/stability_tracker.dart';
import '../../omr/geometry/coordinate_transformer.dart';
import '../../omr/geometry/homography.dart';
import '../../omr/geometry/quadrilateral.dart';
import '../preview/processed_image_screen.dart';

class CameraScreen extends StatefulWidget {
  final AnswerKey answerKey;

  const CameraScreen({super.key, required this.answerKey});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitializing = true;
  bool _isProcessing = false;
  String? _cameraErrorMessage;
  final ImagePicker _imagePicker = ImagePicker();
  String? _currentProcessingPath;
  String? _currentRollNumber;
  int _rollCounter = 1;

  // Live CamScanner-Style Detection & Auto-Capture Engine
  late final LiveDocumentDetector _detector;
  final StabilityTracker _tracker = StabilityTracker();
  bool _autoCaptureEnabled = true;
  FlashMode _flashMode = FlashMode.off;
  bool _isAnalyzingFrame = false;
  DateTime _lastFrameTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isCapturingPhoto = false;
  bool _isImageStreamRunning = false;

  Quadrilateral? _currentNormalizedQuad;
  LiveTrackingState _currentTrackingState = LiveTrackingState.searching;
  String _currentStatusMessage = 'Searching for document...';
  double _currentStabilityProgress = 0.0;

  @override
  void initState() {
    super.initState();
    _detector = LiveDocumentDetector(classMode: widget.answerKey.classMode);
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopStreamingSync();
    _controller?.dispose();
    super.dispose();
  }

  void _stopStreamingSync() {
    if (_isImageStreamRunning && _controller != null && _controller!.value.isInitialized) {
      try {
        _controller!.stopImageStream();
      } catch (_) {}
      _isImageStreamRunning = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _stopStreamingSync();
      cameraController.dispose();
      _controller = null;
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _initializeCamera() async {
    setState(() {
      _isCameraInitializing = true;
      _cameraErrorMessage = null;
      _currentNormalizedQuad = null;
      _currentTrackingState = LiveTrackingState.searching;
      _currentStatusMessage = 'Opening camera hardware...';
      _currentStabilityProgress = 0.0;
    });

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _isCameraInitializing = false;
          _cameraErrorMessage = 'No camera found on this device.';
        });
        return;
      }

      // Pick rear/back camera by default
      final backCamera = _cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras.first,
      );

      final controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid ? ImageFormatGroup.yuv420 : ImageFormatGroup.bgra8888,
      );

      await controller.initialize();

      if (!mounted) {
        controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _isCameraInitializing = false;
        _currentStatusMessage = 'Searching for document...';
      });

      // Start live image stream for document detection
      await _startStreaming();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCameraInitializing = false;
          _cameraErrorMessage = 'Could not start camera: $e';
        });
      }
    }
  }

  Future<void> _startStreaming() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_isImageStreamRunning) return;

    try {
      _isImageStreamRunning = true;
      _tracker.reset();
      await _controller!.startImageStream(_onCameraFrame);
    } catch (e) {
      debugPrint('[CAM:STREAM] Could not start image stream: $e');
      _isImageStreamRunning = false;
    }
  }

  Future<void> _stopStreaming() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (!_isImageStreamRunning) return;

    try {
      await _controller!.stopImageStream();
    } catch (e) {
      debugPrint('[CAM:STREAM] Could not stop image stream: $e');
    } finally {
      _isImageStreamRunning = false;
    }
  }

  void _onCameraFrame(CameraImage frame) {
    if (!mounted || _isProcessing || _isCapturingPhoto || _isAnalyzingFrame) return;

    final now = DateTime.now();
    // High-performance live analysis throttled to 25ms (~30-40 FPS) for instant document acquisition
    if (now.difference(_lastFrameTime).inMilliseconds < 25) return;
    _lastFrameTime = now;
    _isAnalyzingFrame = true;

    try {
      final sensorOrientation = _controller?.description.sensorOrientation ?? 90;
      final result = _detector.detectFromCameraImage(frame, sensorOrientation);

      if (!mounted) {
        _isAnalyzingFrame = false;
        return;
      }

      _tracker.update(result);

      setState(() {
        _currentNormalizedQuad = _tracker.smoothedQuad;
        _currentTrackingState = _tracker.state;
        _currentStatusMessage = _tracker.statusMessage;
        _currentStabilityProgress = _tracker.stabilityProgress;
      });

      // Trigger automatic capture when steady criteria are satisfied!
      if (_autoCaptureEnabled && _tracker.shouldAutoCapture && !_isCapturingPhoto && !_isProcessing) {
        _tracker.lockCapture();
        _takePicture(isAutoTriggered: true);
      }
    } catch (e) {
      debugPrint('[CAM:FRAME] Analysis error: $e');
    } finally {
      _isAnalyzingFrame = false;
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      final nextMode = _flashMode == FlashMode.torch ? FlashMode.off : FlashMode.torch;
      await _controller!.setFlashMode(nextMode);
      setState(() => _flashMode = nextMode);
    } catch (e) {
      debugPrint('Could not set flash mode: $e');
    }
  }

  void _toggleAutoCapture() {
    setState(() {
      _autoCaptureEnabled = !_autoCaptureEnabled;
      if (!_autoCaptureEnabled && _tracker.state == LiveTrackingState.readyToCapture) {
        _tracker.reset();
      }
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_autoCaptureEnabled ? 'Auto-capture enabled' : 'Manual capture mode active'),
        duration: const Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<String?> _askRollNumber() async {
    final suggested = '$_rollCounter';
    final roll = await RollNumberDialog.show(context, initialRoll: suggested);
    if (roll != null && roll.isNotEmpty) {
      final parsed = int.tryParse(roll);
      if (parsed != null) {
        _rollCounter = parsed + 1;
      }
      // Allow dialog dismiss transition to cleanly finish without hitching
      await Future.delayed(const Duration(milliseconds: 200));
    }
    return roll;
  }

  Future<void> _takePicture({bool isAutoTriggered = false}) async {
    if (_isProcessing || _isCapturingPhoto) return;

    if (_controller != null && _controller!.value.isInitialized) {
      setState(() {
        _isCapturingPhoto = true;
        _currentTrackingState = LiveTrackingState.capturing;
        _currentStatusMessage = 'Capturing document...';
      });

      // Stop frame streaming BEFORE takePicture() to prevent camera driver deadlock
      await _stopStreaming();

      try {
        final capturedNormQuad = _currentNormalizedQuad;
        final XFile photo = await _controller!.takePicture();

        String roll = '';
        if (widget.answerKey.classMode != 'class_9_10') {
          final askedRoll = await _askRollNumber();
          if (askedRoll == null) {
            // User cancelled roll number entry; resume camera streaming
            setState(() {
              _isCapturingPhoto = false;
              _tracker.reset();
            });
            await _startStreaming();
            return;
          }
          roll = askedRoll;
        }

        // Rectify full-resolution captured photo to guarantee ONLY the detected document is saved (stripping all side noise)
        String finalImagePath = photo.path;
        Quadrilateral? targetQuad;
        try {
          final photoBytes = await File(photo.path).readAsBytes();
          var rawPhoto = img.decodeImage(photoBytes);
          if (rawPhoto != null) {
            rawPhoto = img.bakeOrientation(rawPhoto);

            final isClass910 = widget.answerKey.classMode == 'class_9_10';

            // Tier 1: High-resolution direct sheet contour detection on the captured photo
            final sheetRes = const SheetDetector().detectSheet(rawPhoto);
            if (sheetRes.isReliable && !sheetRes.isCropped) {
              targetQuad = sheetRes.quad;
              debugPrint('[CAM:RECTIFY] SheetDetector located corners on photo: $targetQuad');
            } else if (capturedNormQuad != null && capturedNormQuad.isValid()) {
              // Tier 2: Mapped live preview quadrilateral with sensor aspect-ratio compensation
              targetQuad = _mapPreviewQuadToPhoto(
                capturedNormQuad,
                _controller?.value.previewSize,
                rawPhoto.width.toDouble(),
                rawPhoto.height.toDouble(),
              );
              debugPrint('[CAM:RECTIFY] Mapped live preview quad to photo resolution: $targetQuad');
            } else {
              // Tier 3: LiveDocumentDetector directly on rawPhoto
              final liveRes = _detector.detectFromImage(rawPhoto);
              if (liveRes.normalizedQuad != null && liveRes.isReliable) {
                targetQuad = CoordinateTransformer.denormalizeQuad(
                  liveRes.normalizedQuad!,
                  rawPhoto.width.toDouble(),
                  rawPhoto.height.toDouble(),
                );
                debugPrint('[CAM:RECTIFY] LiveDocumentDetector located sheet on photo: $targetQuad');
              }
            }

            if (targetQuad != null && targetQuad.isValid()) {
              final isPortrait = targetQuad.targetMaxHeight > targetQuad.targetMaxWidth;
              final int targetW = isClass910
                  ? Class910Detector.canonicalSheetWidth
                  : (isPortrait ? 1120 : 1536);
              final int targetH = isClass910
                  ? Class910Detector.canonicalSheetHeight
                  : (isPortrait ? 1536 : 1120);

              final rectified = HomographyMatrix.warpPerspective(rawPhoto, targetQuad, targetW, targetH);
              final rectifiedPath = photo.path.replaceAll(
                RegExp(r'\.(jpg|jpeg|png)$', caseSensitive: false),
                '_rectified.jpg',
              );
              final savePath = rectifiedPath == photo.path ? '${photo.path}_rectified.jpg' : rectifiedPath;
              await File(savePath).writeAsBytes(img.encodeJpg(rectified, quality: 92));
              finalImagePath = savePath;
              debugPrint('[CAM:RECTIFY] Warped document to canonical canvas ${targetW}x$targetH (side noise completely eliminated)');
            } else {
              // Could not reliably locate physical sheet corners for perspective rectification
              setState(() {
                _isProcessing = false;
                _isCapturingPhoto = false;
                _tracker.reset();
              });
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Could not detect sheet boundaries clearly. Please align sheet inside frame and retake.'),
                    backgroundColor: Colors.red,
                    duration: Duration(seconds: 3),
                  ),
                );
              }
              await _startStreaming();
              return;
            }
          }
        } catch (e) {
          debugPrint('[CAM:RECTIFY] Perspective correction fallback: $e');
        }

        await _processScan(
          finalImagePath,
          roll,
          detectedQuad: targetQuad,
        );
      } catch (e) {
        setState(() {
          _isProcessing = false;
          _isCapturingPhoto = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to take picture: $e'), backgroundColor: Colors.red),
          );
        }
        await _startStreaming();
      }
    } else {
      // Fallback: system camera app intent
      _pickFromSystemCamera();
    }
  }

  /// Maps normalized preview quadrilateral to captured high-resolution photo dimensions,
  /// compensating for aspect-ratio differences between the camera preview and photo sensor.
  Quadrilateral _mapPreviewQuadToPhoto(
    Quadrilateral previewNormQuad,
    Size? previewSize,
    double photoWidth,
    double photoHeight,
  ) {
    if (previewSize == null || photoWidth <= 0 || photoHeight <= 0) {
      return CoordinateTransformer.denormalizeQuad(previewNormQuad, photoWidth, photoHeight);
    }

    final double prevLong = max(previewSize.width, previewSize.height);
    final double prevShort = min(previewSize.width, previewSize.height);
    final double prevAspect = prevLong / prevShort;

    final double photoLong = max(photoWidth, photoHeight);
    final double photoShort = min(photoWidth, photoHeight);
    final double photoAspect = photoLong / photoShort;

    Point2D mapPoint(Point2D pt) {
      double normX = pt.x;
      double normY = pt.y;

      if ((prevAspect - photoAspect).abs() > 0.05) {
        if (prevAspect > photoAspect) {
          // Preview is narrower/taller (e.g. 16:9) than photo sensor (e.g. 4:3).
          final scaleX = (prevShort / prevLong) / (photoShort / photoLong);
          normX = (0.5 + (normX - 0.5) * scaleX).clamp(0.0, 1.0);
        } else {
          // Photo is narrower than preview.
          final scaleY = (photoShort / photoLong) / (prevShort / prevLong);
          normY = (0.5 + (normY - 0.5) * scaleY).clamp(0.0, 1.0);
        }
      }

      return Point2D(
        (normX * photoWidth).clamp(0.0, photoWidth - 1),
        (normY * photoHeight).clamp(0.0, photoHeight - 1),
      );
    }

    return Quadrilateral(
      tl: mapPoint(previewNormQuad.tl),
      tr: mapPoint(previewNormQuad.tr),
      br: mapPoint(previewNormQuad.br),
      bl: mapPoint(previewNormQuad.bl),
    );
  }

  Future<void> _pickFromSystemCamera() async {
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
      );
      if (photo != null) {
        String roll = '';
        if (widget.answerKey.classMode != 'class_9_10') {
          final askedRoll = await _askRollNumber();
          if (askedRoll == null) return;
          roll = askedRoll;
        }

        // Rectify system camera photo to eliminate side noise
        String processedPath = photo.path;
        try {
          final bytes = await File(photo.path).readAsBytes();
          var imgFile = img.decodeImage(bytes);
          if (imgFile != null) {
            imgFile = img.bakeOrientation(imgFile);
            final sheetRes = const SheetDetector().detectSheet(imgFile);
            if (sheetRes.isReliable && !sheetRes.isCropped) {
              final isClass910 = widget.answerKey.classMode == 'class_9_10';
              final isPortrait = sheetRes.quad.targetMaxHeight > sheetRes.quad.targetMaxWidth;
              final int targetW = isClass910
                  ? Class910Detector.canonicalSheetWidth
                  : (isPortrait ? 1120 : 1536);
              final int targetH = isClass910
                  ? Class910Detector.canonicalSheetHeight
                  : (isPortrait ? 1536 : 1120);
              final rectified = HomographyMatrix.warpPerspective(imgFile, sheetRes.quad, targetW, targetH);
              final rectifiedPath = photo.path.replaceAll(
                RegExp(r'\.(jpg|jpeg|png)$', caseSensitive: false),
                '_rectified.jpg',
              );
              final savePath = rectifiedPath == photo.path ? '${photo.path}_rectified.jpg' : rectifiedPath;
              await File(savePath).writeAsBytes(img.encodeJpg(rectified, quality: 92));
              processedPath = savePath;
              debugPrint('[SYSCAM:RECTIFY] Warped document to canonical canvas ${targetW}x$targetH (side noise eliminated)');
            }
          }
        } catch (_) {}

        await _processScan(processedPath, roll);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera picker error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickFromStorage() async {
    if (_isProcessing || _isCapturingPhoto) return;

    await _stopStreaming();

    try {
      final XFile? file = await _imagePicker.pickImage(
        source: ImageSource.gallery,
      );

      if (file != null) {
        String roll = '';
        if (widget.answerKey.classMode != 'class_9_10') {
          final askedRoll = await _askRollNumber();
          if (askedRoll == null) {
            await _startStreaming();
            return;
          }
          roll = askedRoll;
        }

        // Rectify gallery photo to eliminate side noise
        String processedPath = file.path;
        try {
          final bytes = await File(file.path).readAsBytes();
          var imgFile = img.decodeImage(bytes);
          if (imgFile != null) {
            imgFile = img.bakeOrientation(imgFile);
            final sheetRes = const SheetDetector().detectSheet(imgFile);
            if (sheetRes.isReliable && !sheetRes.isCropped) {
              final isClass910 = widget.answerKey.classMode == 'class_9_10';
              final isPortrait = sheetRes.quad.targetMaxHeight > sheetRes.quad.targetMaxWidth;
              final int targetW = isClass910
                  ? Class910Detector.canonicalSheetWidth
                  : (isPortrait ? 1120 : 1536);
              final int targetH = isClass910
                  ? Class910Detector.canonicalSheetHeight
                  : (isPortrait ? 1536 : 1120);
              final rectified = HomographyMatrix.warpPerspective(imgFile, sheetRes.quad, targetW, targetH);
              final rectifiedPath = file.path.replaceAll(
                RegExp(r'\.(jpg|jpeg|png)$', caseSensitive: false),
                '_rectified.jpg',
              );
              final savePath = rectifiedPath == file.path ? '${file.path}_rectified.jpg' : rectifiedPath;
              await File(savePath).writeAsBytes(img.encodeJpg(rectified, quality: 92));
              processedPath = savePath;
              debugPrint('[STORAGE:RECTIFY] Warped document to canonical canvas ${targetW}x$targetH (side noise eliminated)');
            }
          }
        } catch (_) {}

        await _processScan(processedPath, roll);
      } else {
        await _startStreaming();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open storage: $e'), backgroundColor: Colors.red),
        );
      }
      await _startStreaming();
    }
  }

  Future<void> _processScan(String imagePath, String rollNumber, {Quadrilateral? detectedQuad}) async {
    setState(() {
      _isProcessing = true;
      _currentProcessingPath = imagePath;
      _currentRollNumber = rollNumber;
    });

    // Yield frame so the laser scanner animation mounts and renders initial sweep
    await Future.delayed(const Duration(milliseconds: 150));

    try {
      final omrService = OmrService();
      final stopwatch = Stopwatch()..start();
      final scanResult = await omrService.scanImage(
        imagePath,
        classMode: widget.answerKey.classMode,
        detectedQuad: detectedQuad,
      );

      // Ensure laser animation runs cleanly for at least 800ms
      final elapsed = stopwatch.elapsedMilliseconds;
      if (elapsed < 800) {
        await Future.delayed(Duration(milliseconds: 800 - elapsed));
      }

      if (!mounted) return;

      if (scanResult.status == ScanStatus.failed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(scanResult.message), backgroundColor: Colors.red),
        );
        setState(() {
          _isProcessing = false;
          _isCapturingPhoto = false;
          _tracker.reset();
        });
        await _startStreaming();
        return;
      }

      setState(() {
        _isProcessing = false;
        _isCapturingPhoto = false;
      });

      final effectiveRoll = rollNumber.isNotEmpty ? rollNumber : scanResult.rollNumber;

      // Navigate to Processed Image Screen (Detected Circles Overlay) before Review
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProcessedImageScreen(
            scanResult: scanResult,
            answerKey: widget.answerKey,
            rollNumber: effectiveRoll,
          ),
        ),
      );

      // If user navigated back (e.g. tapped 'Retake'), resume live camera streaming
      if (mounted) {
        _tracker.reset();
        setState(() {
          _currentNormalizedQuad = null;
          _currentTrackingState = LiveTrackingState.searching;
          _currentStatusMessage = 'Searching for document...';
          _currentStabilityProgress = 0.0;
        });
        await _startStreaming();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error during scan: $e'), backgroundColor: Colors.red),
        );
        setState(() {
          _isProcessing = false;
          _isCapturingPhoto = false;
        });
        await _startStreaming();
      }
    }
  }

  void _showUserManualDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 440),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFF334155)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.menu_book_rounded, color: Color(0xFF2DD4BF), size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Live Scanner Guide',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'CamScanner-style automatic sheet capture',
                          style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                '• Automatic Detection: Point your camera at the OMR sheet. A green boundary will outline the sheet in real time.\n\n'
                '• Auto-Capture: Hold steady once the green outline locks on the sheet. The scanner will automatically capture and rectify the document.\n\n'
                '• Manual Shutter: You can tap the round shutter button at any time to take an immediate scan.\n\n'
                '• Flash & Lighting: Use the top Flash toggle in dim environments to illuminate answer bubbles.',
                style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 13, height: 1.45),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4338CA),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCameraReady = _controller != null && _controller!.value.isInitialized;

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A).withValues(alpha: 0.85),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.answerKey.examName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const Text(
              'Bangla 30-Question OMR Format',
              style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
            ),
          ],
        ),
        actions: [
          // Flash Toggle Button
          IconButton(
            icon: Icon(
              _flashMode == FlashMode.torch ? Icons.flash_on_rounded : Icons.flash_off_rounded,
              color: _flashMode == FlashMode.torch ? const Color(0xFFFBBF24) : Colors.white70,
            ),
            tooltip: _flashMode == FlashMode.torch ? 'Turn Flash Off' : 'Turn Flash On',
            onPressed: isCameraReady ? _toggleFlash : null,
          ),
          // Auto-Capture Toggle Button
          IconButton(
            icon: Icon(
              _autoCaptureEnabled ? Icons.auto_awesome : Icons.touch_app_rounded,
              color: _autoCaptureEnabled ? const Color(0xFF2DD4BF) : Colors.white60,
            ),
            tooltip: _autoCaptureEnabled ? 'Auto-Capture: ON' : 'Auto-Capture: OFF (Manual)',
            onPressed: _toggleAutoCapture,
          ),
          // Switch / Reconnect Camera
          IconButton(
            icon: const Icon(Icons.flip_camera_android_rounded),
            tooltip: 'Switch / Reconnect Camera',
            onPressed: _initializeCamera,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Full-Screen Live Camera Feed
          if (isCameraReady)
            LayoutBuilder(
              builder: (context, constraints) {
                final previewSize = _controller!.value.previewSize;
                final previewAspect = previewSize != null
                    ? (previewSize.height / previewSize.width)
                    : (1 / _controller!.value.aspectRatio);

                return ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.center,
                    maxWidth: double.infinity,
                    maxHeight: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.cover,
                      child: SizedBox(
                        width: constraints.maxHeight * previewAspect,
                        height: constraints.maxHeight,
                        child: CameraPreview(
                          _controller!,
                          child: LiveScanOverlay(
                            normalizedQuad: _currentNormalizedQuad,
                            trackingState: _currentTrackingState,
                            statusMessage: _currentStatusMessage,
                            stabilityProgress: _currentStabilityProgress,
                            isCapturing: _isCapturingPhoto,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            )
          else if (_isCameraInitializing)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF0D9488)),
                  SizedBox(height: 16),
                  Text(
                    'Opening camera hardware...',
                    style: TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                ],
              ),
            )
          else
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E293B),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF334155)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(
                          color: Color(0xFF334155),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.videocam_off_rounded, size: 48, color: Color(0xFF94A3B8)),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Direct Camera Feed Unavailable',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _cameraErrorMessage ?? 'You can still grade sheets by choosing an image file or launching your device camera.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton.icon(
                          onPressed: _pickFromStorage,
                          icon: const Icon(Icons.folder_open_rounded, size: 20),
                          label: const Text('Add File from Device Storage', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4338CA),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: OutlinedButton.icon(
                          onPressed: _pickFromSystemCamera,
                          icon: const Icon(Icons.camera_alt_rounded, size: 20),
                          label: const Text('Open System Camera'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF475569)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: TextButton.icon(
                          onPressed: _showUserManualDialog,
                          icon: const Icon(Icons.menu_book_rounded, color: Color(0xFF0D9488), size: 20),
                          label: const Text('View User Manual & Guide', style: TextStyle(color: Color(0xFF2DD4BF))),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // 2. Processing overlay with high-tech laser scanner animation
          if (_isProcessing)
            Container(
              color: Colors.black.withValues(alpha: 0.82),
              alignment: Alignment.center,
              child: DocumentScanningAnimation(
                imagePath: _currentProcessingPath,
                rollNumber: _currentRollNumber,
                examTitle: widget.answerKey.examName,
              ),
            ),

          // 3. Bottom Control Bar with Shutter, Storage File Picker, and Sample
          Positioned(
            bottom: 28,
            left: 16,
            right: 16,
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 420),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A).withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: const Color(0xFF334155)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Button 1: Device Storage / Gallery
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _isProcessing || _isCapturingPhoto ? null : _pickFromStorage,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E293B),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFF334155)),
                                ),
                                child: const Icon(Icons.photo_library_rounded, color: Colors.white, size: 22),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Files',
                                style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 11, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Button 2: Shutter Button with Circular Progress for Auto-Capture
                    GestureDetector(
                      onTap: _isProcessing || _isCapturingPhoto ? null : () => _takePicture(isAutoTriggered: false),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (_currentTrackingState == LiveTrackingState.steady && _currentStabilityProgress > 0)
                            SizedBox(
                              width: 80,
                              height: 80,
                              child: CircularProgressIndicator(
                                value: _currentStabilityProgress,
                                strokeWidth: 4,
                                color: const Color(0xFF10B981),
                                backgroundColor: Colors.white24,
                              ),
                            ),
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _currentTrackingState == LiveTrackingState.steady
                                    ? const Color(0xFF10B981)
                                    : Colors.white,
                                width: 3.5,
                              ),
                              color: Colors.white.withValues(alpha: 0.15),
                              boxShadow: [
                                BoxShadow(
                                  color: (_currentTrackingState == LiveTrackingState.steady
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFF4338CA))
                                      .withValues(alpha: 0.35),
                                  blurRadius: 12,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Center(
                              child: Container(
                                width: 54,
                                height: 54,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: _currentTrackingState == LiveTrackingState.steady
                                        ? [const Color(0xFFD1FAE5), const Color(0xFFA7F3D0)]
                                        : [Colors.white, const Color(0xFFF1F5F9)],
                                  ),
                                ),
                                child: Icon(
                                  _autoCaptureEnabled && _currentTrackingState == LiveTrackingState.steady
                                      ? Icons.auto_awesome
                                      : Icons.camera_alt_rounded,
                                  color: const Color(0xFF0F172A),
                                  size: 26,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Button 3: User Manual / Guidelines
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: _showUserManualDialog,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF064E3B),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0xFF059669)),
                                ),
                                child: const Icon(Icons.menu_book_rounded, color: Color(0xFF34D399), size: 22),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Manual',
                                style: TextStyle(color: Color(0xFF34D399), fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
