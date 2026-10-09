import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../utils/image_compress_helper.dart';
import 'camera/camera_stub_controller.dart'
    if (dart.library.html) 'camera/camera_web_controller.dart';

/// Full-screen in-app camera viewfinder designed exactly like WhatsApp:
/// - Fast continuous multi-photo snapping with ZERO retake delay
/// - Camera stays live so users can snap page 1, page 2, page 3 rapidly
/// - Floating horizontal thumbnail tray with one-tap [✕] remove button
/// - WhatsApp green confirm checkmark button `[✓ X]` to return all photos
/// - Gallery picker supports selecting multiple photos directly
/// - Tap to focus with authentic yellow animated reticle
/// - Flash toggle [Off / On / Auto] and Camera flip [🔄]
class InAppBillCameraScreen extends StatefulWidget {
  const InAppBillCameraScreen({super.key});

  @override
  State<InAppBillCameraScreen> createState() => _InAppBillCameraScreenState();
}

class _InAppBillCameraScreenState extends State<InAppBillCameraScreen> {
  final WebCameraHelper _cameraHelper = WebCameraHelper();
  final ImagePicker _picker = ImagePicker();
  final ScrollController _thumbScrollController = ScrollController();

  bool _isInitializing = true;
  String? _initError;
  final List<String> _capturedPhotos = [];
  bool _isCapturing = false;
  bool _showShutterFlash = false;

  // Tap-to-focus animation state
  Offset? _focusPoint;
  Timer? _focusTimer;

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
          if (mounted) Navigator.pop(context, [b64]);
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
    if (_isCapturing) return;
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

    // Brief shutter flash feedback (WhatsApp shutter pulse)
    Future.delayed(const Duration(milliseconds: 70), () {
      if (mounted) setState(() => _showShutterFlash = false);
    });

    try {
      final b64 = await _cameraHelper.capturePhotoBase64();
      if (b64 != null && b64.isNotEmpty) {
        setState(() {
          _capturedPhotos.add(b64);
          _isCapturing = false;
        });
        _scrollToEnd();
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
    if (_isCapturing) return;
    try {
      final List<XFile> pickedList = await _picker.pickMultiImage(
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
      );
      if (pickedList.isNotEmpty) {
        for (final picked in pickedList) {
          final bytes = await picked.readAsBytes();
          final b64 = ImageCompressHelper.compressToBase64(bytes);
          _capturedPhotos.add(b64);
        }
        if (mounted) {
          setState(() {});
          _scrollToEnd();
        }
      }
    } catch (e) {
      debugPrint('Gallery pick error, trying single: $e');
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
              _capturedPhotos.add(b64);
            });
            _scrollToEnd();
          }
        }
      } catch (_) {}
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_thumbScrollController.hasClients) {
        _thumbScrollController.animateTo(
          _thumbScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _finishAndReturn() {
    if (_capturedPhotos.isEmpty) return;
    Navigator.pop(context, List<String>.from(_capturedPhotos));
  }

  void _onClosePressed() {
    if (_capturedPhotos.isNotEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'Discard Photos?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Text(
            'You have ${_capturedPhotos.length} captured photo${_capturedPhotos.length > 1 ? 's' : ''}. Do you want to discard them?',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Keep Snapping', style: TextStyle(color: Color(0xFF25D366))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE11D48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context, null);
              },
              child: const Text('Discard', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } else {
      Navigator.pop(context, null);
    }
  }

  @override
  void dispose() {
    _focusTimer?.cancel();
    _thumbScrollController.dispose();
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
            // 1. LIVE CAMERA VIEWFINDER (Always active - zero review delay)
            if (_isInitializing)
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

                      // Tap-to-focus animation reticle (WhatsApp yellow ring)
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

            // 2. SHUTTER SNAP WHITE FLASH BURST (Authentic quick camera feedback)
            if (_showShutterFlash)
              Positioned.fill(
                child: Container(color: Colors.white.withValues(alpha: 0.85)),
              ),

            // 3. TOP ACTION BAR
            Positioned(
              top: 14,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // [✕] Close button
                  GestureDetector(
                    onTap: _onClosePressed,
                    child: Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white24, width: 1),
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 22),
                    ),
                  ),

                  // Middle Photo Count Badge (if photos captured)
                  if (_capturedPhotos.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF25D366).withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            '${_capturedPhotos.length} photo${_capturedPhotos.length > 1 ? 's' : ''} added',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Right Actions: Flip Camera + Flash Toggle
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Flip Camera button
                      GestureDetector(
                        onTap: _flipCamera,
                        child: Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white24, width: 1),
                          ),
                          child: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white, size: 20),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // WhatsApp Flash Toggle Button [Off / On / Auto]
                      GestureDetector(
                        onTap: _toggleFlash,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
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
                                size: 20,
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
                ],
              ),
            ),

            // 4. BOTTOM CONTROLS & THUMBNAILS TRAY
            if (!_isInitializing && _initError == null)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.only(top: 14, bottom: 22, left: 16, right: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.95),
                        Colors.black.withValues(alpha: 0.5),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Multi-photo Horizontal Thumbnail Strip (WhatsApp style)
                      _buildThumbnailStrip(),

                      // Shutter Action Bar: [Gallery 🖼️]  [⚪ WhatsApp Shutter]  [Done ✓ / Flip]
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Gallery Button
                          GestureDetector(
                            onTap: _pickFromGallery,
                            child: Container(
                              width: 54,
                              height: 54,
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

                          // WhatsApp Shutter Button (Outer ring + Inner circle)
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

                          // Right Action: WhatsApp Iconic Green Confirm Checkmark [✓]
                          if (_capturedPhotos.isNotEmpty)
                            GestureDetector(
                              onTap: _finishAndReturn,
                              child: Container(
                                width: 56,
                                height: 56,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF25D366), // WhatsApp primary green
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color(0x7725D366),
                                      blurRadius: 12,
                                      spreadRadius: 2,
                                      offset: Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    const Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: 32,
                                    ),
                                    Positioned(
                                      top: 2,
                                      right: 3,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        decoration: const BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Text(
                                          '${_capturedPhotos.length}',
                                          style: const TextStyle(
                                            color: Color(0xFF128C7E),
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            // Placeholder container for symmetrical alignment
                            GestureDetector(
                              onTap: _flipCamera,
                              child: Container(
                                width: 54,
                                height: 54,
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
                      const SizedBox(height: 12),

                      // "PHOTO" Mode indicator
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.circle, size: 7, color: Color(0xFF25D366)),
                            const SizedBox(width: 6),
                            Text(
                              _capturedPhotos.isEmpty
                                  ? 'TAP SHUTTER TO SNAP'
                                  : 'TAP GREEN [✓] WHEN DONE (${_capturedPhotos.length})',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
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

  Widget _buildThumbnailStrip() {
    if (_capturedPhotos.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 78,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListView.separated(
        controller: _thumbScrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _capturedPhotos.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final b64 = _capturedPhotos[index];
          final bytes = ImageCompressHelper.safeBase64Decode(b64);

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 60,
                height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.5),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: bytes != null
                      ? Image.memory(
                          bytes,
                          fit: BoxFit.cover,
                          filterQuality: FilterQuality.low,
                        )
                      : Container(
                          color: Colors.grey.shade900,
                          child: const Icon(Icons.image, color: Colors.white54, size: 24),
                        ),
                ),
              ),
              // [✕] Delete badge on thumbnail top-right
              Positioned(
                top: -5,
                right: -5,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _capturedPhotos.removeAt(index);
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Color(0xFFE11D48), // Rose red
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black45,
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 13,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              // Photo index badge on thumbnail bottom-left
              Positioned(
                bottom: 3,
                left: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
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
