import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/image_compress_helper.dart';
import 'camera/camera_stub_controller.dart'
    if (dart.library.html) 'camera/camera_web_controller.dart';

/// Full-screen in-app camera viewfinder matching WhatsApp/Telegram layout:
/// - Top-left [✕] close button
/// - Full-screen live camera stream
/// - Bottom bar: [Gallery 🖼️] on left, [Shutter ⚪] in center, [Flip Camera 🔄] on right
/// - Dedicated Photo mode (no video) specifically for crisp bill capturing.
class InAppBillCameraScreen extends StatefulWidget {
  const InAppBillCameraScreen({super.key});

  @override
  State<InAppBillCameraScreen> createState() => _InAppBillCameraScreenState();
}

class _InAppBillCameraScreenState extends State<InAppBillCameraScreen> {
  final WebCameraHelper _cameraHelper = WebCameraHelper();
  final ImagePicker _picker = ImagePicker();

  bool _isInitializing = true;
  String? _initError;
  String? _capturedPhotoBase64;
  bool _isCapturing = false;

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
      // Non-web fallback: directly use image picker camera
      try {
        final picked = await _picker.pickImage(
          source: ImageSource.camera,
          preferredCameraDevice: CameraDevice.rear,
          maxWidth: 2048,
          maxHeight: 2048,
          imageQuality: 88,
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

  Future<void> _takePhoto() async {
    if (_isCapturing || !_cameraHelper.isReady) return;

    setState(() => _isCapturing = true);
    try {
      final b64 = await _cameraHelper.capturePhotoBase64();
      if (b64 != null && b64.isNotEmpty) {
        setState(() {
          _capturedPhotoBase64 = b64;
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
        imageQuality: 88,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        final b64 = ImageCompressHelper.compressToBase64(bytes);
        if (mounted) {
          setState(() {
            _capturedPhotoBase64 = b64;
          });
        }
      }
    } catch (e) {
      debugPrint('Gallery pick error: $e');
    }
  }

  void _useCapturedPhoto() {
    if (_capturedPhotoBase64 != null) {
      Navigator.pop(context, _capturedPhotoBase64);
    }
  }

  void _retakePhoto() {
    setState(() {
      _capturedPhotoBase64 = null;
    });
  }

  @override
  void dispose() {
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
            // 1. LIVE CAMERA VIEWFINDER OR REVIEW
            if (_capturedPhotoBase64 != null)
              _buildPhotoReview()
            else if (_isInitializing)
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      'Opening camera...',
                      style: TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ),
              )
            else if (_initError != null)
              _buildErrorFallback()
            else
              Positioned.fill(
                child: _cameraHelper.buildPreview(),
              ),

            // 2. TOP CONTROLS (Only visible if not in review mode)
            if (_capturedPhotoBase64 == null)
              Positioned(
                top: 16,
                left: 16,
                right: 16,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Close button [✕]
                    GestureDetector(
                      onTap: () => Navigator.pop(context, null),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 24),
                      ),
                    ),

                    // Title pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long, size: 14, color: Colors.white),
                          SizedBox(width: 6),
                          Text(
                            'Scan Bill Photo',
                            style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 44), // Balances top row
                  ],
                ),
              ),

            // 3. BOTTOM CONTROLS (Only visible if not in review mode and camera is ready)
            if (_capturedPhotoBase64 == null && !_isInitializing && _initError == null)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.only(top: 20, bottom: 28, left: 24, right: 24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.85),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Shutter Row: [Gallery 🖼️]  [⚪ Shutter]  [🔄 Flip]
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

                          // Large Shutter Button
                          GestureDetector(
                            onTap: _takePhoto,
                            child: Container(
                              width: 78,
                              height: 78,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 4),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.4),
                                    blurRadius: 10,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Container(
                                  width: 62,
                                  height: 62,
                                  decoration: const BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.circle,
                                  ),
                                  child: _isCapturing
                                      ? const Center(
                                          child: SizedBox(
                                            width: 24,
                                            height: 24,
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
                        child: const Text(
                          'PHOTO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                          ),
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
      child: Column(
        children: [
          // Captured Image preview
          Expanded(
            child: bytes != null
                ? Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                    width: double.infinity,
                  )
                : const Center(
                    child: Icon(Icons.broken_image, size: 60, color: Colors.white54),
                  ),
          ),

          // Bottom Confirmation Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            color: const Color(0xFF0F172A),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Retake', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _retakePhoto,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle_rounded, size: 18),
                    label: const Text('Use Photo', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 2,
                    ),
                    onPressed: _useCapturedPhoto,
                  ),
                ),
              ],
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
                backgroundColor: const Color(0xFF10B981),
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
