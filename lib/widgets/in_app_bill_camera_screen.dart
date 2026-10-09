import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import '../utils/image_compress_helper.dart';
import 'camera/camera_stub_controller.dart'
    if (dart.library.html) 'camera/camera_web_controller.dart';

/// Full-screen in-app camera viewfinder designed exactly like WhatsApp:
/// - Top-left: [✕] Close button
/// - Top-right: [⚡] Flash / Torch toggle (Off, On, Auto)
/// - Tap to focus with authentic yellow animated reticle
/// - Bottom bar: [Gallery 🖼️] on left, WhatsApp shutter [⚪] in center, [Flip Camera 🔄] on right
/// - Review screen with 90° rotation tool and iconic WhatsApp Green checkmark button.
class InAppBillCameraScreen extends StatefulWidget {
  const InAppBillCameraScreen({super.key});

  @override
  State<InAppBillCameraScreen> createState() => _InAppBillCameraScreenState();
}

class _InAppBillCameraScreenState extends State<InAppBillCameraScreen> with SingleTickerProviderStateMixin {
  final WebCameraHelper _cameraHelper = WebCameraHelper();
  final ImagePicker _picker = ImagePicker();

  bool _isInitializing = true;
  String? _initError;
  String? _capturedPhotoBase64;
  bool _isCapturing = false;
  bool _showShutterFlash = false;

  // Tap-to-focus animation state
  Offset? _focusPoint;
  Timer? _focusTimer;

  // Photo review rotation
  int _rotationDegrees = 0;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    setState(() {
      _isInitializing = true;
      _initError = null;
    });

    if (!kIsWeb) {
      // Non-web fallback: directly use image picker camera in HD
      try {
        final picked = await _picker.pickImage(
          source: ImageSource.camera,
          preferredCameraDevice: CameraDevice.rear,
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 90,
        );
        if (picked != null) {
          final bytes = await picked.readAsBytes();
          final b64 = ImageCompressHelper.compressToBase64(bytes);
          if (mounted) Navigator.pop(context, b64);
        } else {
          if (mounted) Navigator.pop(context, null);
        }
      } catch (e) {
        setState(() {
          _isInitializing = false;
          _initError = 'Camera error: $e';
        });
      }
      return;
    }

    try {
      await _cameraHelper.initialize(frontCamera: false);
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
          _initError = 'Could not access camera. Please allow camera permissions in your browser.';
        });
      }
    }
  }

  Future<void> _toggleFlash() async {
    if (_isCapturing) return;
    await _cameraHelper.cycleFlashMode();
    if (mounted) setState(() {});
  }

  void _onViewfinderTap(TapDownDetails details) {
    if (_isCapturing || _capturedPhotoBase64 != null) return;
    _focusTimer?.cancel();
    setState(() {
      _focusPoint = details.localPosition;
    });
    _focusTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) {
        setState(() {
          _focusPoint = null;
        });
      }
    });
  }

  Future<void> _takePhoto() async {
    if (_isCapturing || !_cameraHelper.isReady) return;

    setState(() {
      _isCapturing = true;
      _showShutterFlash = true;
    });

    // Brief shutter flash feedback
    Future.delayed(const Duration(milliseconds: 80), () {
      if (mounted) setState(() => _showShutterFlash = false);
    });

    try {
      final b64 = await _cameraHelper.capturePhotoBase64();
      if (b64 != null && b64.isNotEmpty) {
        setState(() {
          _capturedPhotoBase64 = b64;
          _rotationDegrees = 0;
          _isCapturing = false;
        });
      } else {
        setState(() => _isCapturing = false);
      }
    } catch (e) {
      debugPrint('Capture error: $e');
      setState(() => _isCapturing = false);
    }
  }

  Future<void> _flipCamera() async {
    if (_isCapturing) return;
    setState(() => _isInitializing = true);
    try {
      await _cameraHelper.flipCamera();
    } catch (_) {}
    if (mounted) {
      setState(() => _isInitializing = false);
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        final b64 = ImageCompressHelper.compressToBase64(bytes);
        if (mounted) {
          setState(() {
            _capturedPhotoBase64 = b64;
            _rotationDegrees = 0;
          });
        }
      }
    } catch (e) {
      debugPrint('Gallery pick error: $e');
    }
  }

  void _rotatePhoto() {
    setState(() {
      _rotationDegrees = (_rotationDegrees + 90) % 360;
    });
  }

  void _useCapturedPhoto() {
    if (_capturedPhotoBase64 == null) return;

    if (_rotationDegrees == 0) {
      Navigator.pop(context, _capturedPhotoBase64);
      return;
    }

    // Apply rotation before returning
    try {
      final bytes = ImageCompressHelper.safeBase64Decode(_capturedPhotoBase64);
      if (bytes != null) {
        final decoded = img.decodeImage(bytes);
        if (decoded != null) {
          final rotated = img.copyRotate(decoded, angle: _rotationDegrees);
          final encoded = img.encodeJpg(rotated, quality: 90);
          Navigator.pop(context, base64Encode(encoded));
          return;
        }
      }
    } catch (_) {}

    Navigator.pop(context, _capturedPhotoBase64);
  }

  void _retakePhoto() {
    setState(() {
      _capturedPhotoBase64 = null;
      _rotationDegrees = 0;
    });
  }

  @override
  void dispose() {
    _focusTimer?.cancel();
    _cameraHelper.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. LIVE CAMERA VIEWFINDER OR PHOTO REVIEW
            if (_capturedPhotoBase64 != null)
              _buildPhotoReview()
            else if (_isInitializing)
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Color(0xFF25D366)),
                    SizedBox(height: 16),
                    Text(
                      'Starting camera...',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              )
            else if (_initError != null)
              _buildErrorFallback()
            else
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: _onViewfinderTap,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _cameraHelper.buildPreview(),

                      // Tap-to-focus animation reticle (WhatsApp/iPhone style yellow ring)
                      if (_focusPoint != null)
                        Positioned(
                          left: _focusPoint!.dx - 32,
                          top: _focusPoint!.dy - 32,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 1.3, end: 1.0),
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeOutBack,
                            builder: (context, scale, child) {
                              return Transform.scale(
                                scale: scale,
                                child: Container(
                                  width: 64,
                                  height: 64,
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.amberAccent, width: 1.8),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Center(
                                    child: Icon(Icons.add, size: 14, color: Colors.amberAccent),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),

            // 2. SHUTTER SNAP WHITE FLASH BURST
            if (_showShutterFlash)
              Positioned.fill(
                child: Container(color: Colors.white.withValues(alpha: 0.85)),
              ),

            // 3. WHATSAPP TOP CONTROLS (Only visible during live camera mode)
            if (_capturedPhotoBase64 == null)
              Positioned(
                top: 14,
                left: 16,
                right: 16,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // [✕] Close button
                    GestureDetector(
                      onTap: () => Navigator.pop(context, null),
                      child: Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 24),
                      ),
                    ),

                    // WhatsApp Flash Toggle Button [Off / On / Auto]
                    GestureDetector(
                      onTap: _toggleFlash,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: _cameraHelper.flashMode == 'on'
                                ? Colors.amberAccent
                                : Colors.white24,
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _cameraHelper.flashMode == 'on'
                                  ? Icons.flash_on_rounded
                                  : _cameraHelper.flashMode == 'auto'
                                      ? Icons.flash_auto_rounded
                                      : Icons.flash_off_rounded,
                              color: _cameraHelper.flashMode == 'on'
                                  ? Colors.amberAccent
                                  : Colors.white,
                              size: 22,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _cameraHelper.flashMode.toUpperCase(),
                              style: TextStyle(
                                color: _cameraHelper.flashMode == 'on'
                                    ? Colors.amberAccent
                                    : Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // 4. WHATSAPP BOTTOM CONTROLS (Gallery | Shutter | Flip Camera)
            if (_capturedPhotoBase64 == null && !_isInitializing && _initError == null)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.only(top: 24, bottom: 28, left: 24, right: 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.9),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Shutter Row: [Gallery 🖼️]  [⚪ WhatsApp Shutter]  [🔄 Flip]
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Gallery Button
                          GestureDetector(
                            onTap: _pickFromGallery,
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white38, width: 1.5),
                              ),
                              child: const Icon(
                                Icons.photo_library_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),

                          // WhatsApp Shutter Button (Outer white ring + Inner solid white circle)
                          GestureDetector(
                            onTap: _takePhoto,
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.5),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Container(
                                  width: 64,
                                  height: 64,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: _isCapturing
                                      ? const Center(
                                          child: SizedBox(
                                            width: 26,
                                            height: 26,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              color: Colors.black,
                                            ),
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),

                          // Flip Camera Button
                          GestureDetector(
                            onTap: _flipCamera,
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white38, width: 1.5),
                              ),
                              child: const Icon(
                                Icons.flip_camera_ios_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // "PHOTO" Mode indicator
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.circle, size: 7, color: Color(0xFF25D366)),
                            SizedBox(width: 6),
                            Text(
                              'PHOTO',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoReview() {
    final bytes = ImageCompressHelper.safeBase64Decode(_capturedPhotoBase64);

    return Container(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Captured Photo with rotation
          Center(
            child: bytes != null
                ? RotatedBox(
                    quarterTurns: (_rotationDegrees ~/ 90) % 4,
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      width: double.infinity,
                      filterQuality: FilterQuality.high,
                    ),
                  )
                : const Center(
                    child: Icon(Icons.broken_image, size: 60, color: Colors.white54),
                  ),
          ),

          // 2. WhatsApp Top Review Bar (Discard / Back on left, Rotate tool on right)
          Positioned(
            top: 14,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: _retakePhoto,
                  child: Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
                  ),
                ),
                GestureDetector(
                  onTap: _rotatePhoto,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white30),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.rotate_right_rounded, color: Colors.white, size: 20),
                        SizedBox(width: 6),
                        Text(
                          'Rotate',
                          style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 3. WhatsApp Bottom Review Bar (Retake on left, Green Send Checkmark on right)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.9),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Retake Button
                  TextButton.icon(
                    icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
                    label: const Text(
                      'Retake',
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    onPressed: _retakePhoto,
                  ),

                  // WhatsApp Iconic Green Circular Send / Confirm Button
                  GestureDetector(
                    onTap: _useCapturedPhoto,
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: const BoxDecoration(
                        color: Color(0xFF25D366), // WhatsApp primary green
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x6625D366),
                            blurRadius: 12,
                            spreadRadius: 2,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.check_rounded,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorFallback() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.videocam_off_rounded, size: 48, color: Colors.orangeAccent),
            ),
            const SizedBox(height: 16),
            const Text(
              'Camera Access Needed',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _initError ?? 'Please allow camera permission in your browser or choose a saved photo from gallery.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.photo_library_rounded, size: 20),
              label: const Text('Choose Photo from Gallery', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _pickFromGallery,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancel & Go Back', style: TextStyle(color: Colors.white60)),
            ),
          ],
        ),
      ),
    );
  }
}
