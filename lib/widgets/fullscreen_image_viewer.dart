import 'package:flutter/material.dart';
import '../utils/image_compress_helper.dart';

/// Full-screen zoomable image viewer supporting single or multiple images,
/// pinch-to-zoom, scroll-zoom, pan gestures, and multi-page navigation.
class FullScreenImageViewer extends StatefulWidget {
  final String? imageBase64;
  final List<String>? imagesBase64;
  final int initialIndex;
  final String title;
  final String? subtitle;

  const FullScreenImageViewer({
    super.key,
    this.imageBase64,
    this.imagesBase64,
    this.initialIndex = 0,
    required this.title,
    this.subtitle,
  }) : assert(imageBase64 != null || imagesBase64 != null, 'Provide either imageBase64 or imagesBase64');

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  final TransformationController _transformationController = TransformationController();
  late PageController _pageController;
  late int _currentIndex;
  double _currentScale = 1.0;

  List<String> get _images {
    if (widget.imagesBase64 != null && widget.imagesBase64!.isNotEmpty) {
      return widget.imagesBase64!;
    }
    if (widget.imageBase64 != null && widget.imageBase64!.isNotEmpty) {
      return [widget.imageBase64!];
    }
    return const [];
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, (_images.length - 1).clamp(0, 999));
    _pageController = PageController(initialPage: _currentIndex);
    _transformationController.addListener(() {
      final scale = _transformationController.value.getMaxScaleOnAxis();
      if ((scale - _currentScale).abs() > 0.05) {
        setState(() {
          _currentScale = scale;
        });
      }
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  void _zoomIn() {
    final nextScale = (_currentScale * 1.4).clamp(0.5, 6.0);
    _setZoom(nextScale);
  }

  void _zoomOut() {
    final nextScale = (_currentScale / 1.4).clamp(0.5, 6.0);
    _setZoom(nextScale);
  }

  void _resetZoom() {
    _setZoom(1.0);
  }

  void _setZoom(double targetScale) {
    setState(() {
      _currentScale = targetScale;
      _transformationController.value =
          Matrix4.diagonal3Values(targetScale, targetScale, 1.0);
    });
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
    _resetZoom();
  }

  @override
  Widget build(BuildContext context) {
    final images = _images;
    final hasMultiple = images.length > 1;
    final currentImageBase64 = images.isNotEmpty && _currentIndex < images.length
        ? images[_currentIndex]
        : null;
    final imageBytes = currentImageBase64 != null
        ? ImageCompressHelper.safeBase64Decode(currentImageBase64)
        : null;

    final displayTitle = hasMultiple
        ? '${widget.title} (${_currentIndex + 1}/${images.length})'
        : widget.title;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1D),
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.65),
        elevation: 0,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              displayTitle,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            if (widget.subtitle != null)
              Text(
                widget.subtitle!,
                style: const TextStyle(fontSize: 11, color: Colors.white70),
              ),
          ],
        ),
        actions: [
          // Zoom scale badge
          Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${(_currentScale * 100).toInt()}%',
                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out, size: 22),
            tooltip: 'Zoom Out (-)',
            onPressed: _zoomOut,
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in, size: 22),
            tooltip: 'Zoom In (+)',
            onPressed: _zoomIn,
          ),
          IconButton(
            icon: const Icon(Icons.restart_alt, size: 20),
            tooltip: 'Reset Zoom (100%)',
            onPressed: _resetZoom,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Center Image View
          Center(
            child: imageBytes == null
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image, size: 54, color: Colors.white54),
                      SizedBox(height: 12),
                      Text('Image data corrupted or unavailable', style: TextStyle(color: Colors.white70)),
                    ],
                  )
                : InteractiveViewer(
                    transformationController: _transformationController,
                    minScale: 0.5,
                    maxScale: 6.0,
                    panEnabled: true,
                    scaleEnabled: true,
                    clipBehavior: Clip.none,
                    child: Image.memory(
                      imageBytes,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Center(
                          child: Text('Could not render image', style: TextStyle(color: Colors.white)),
                        );
                      },
                    ),
                  ),
          ),

          // Previous / Next overlay buttons for multi-photo navigation
          if (hasMultiple) ...[
            if (_currentIndex > 0)
              Positioned(
                left: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black54,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.chevron_left, size: 30),
                    tooltip: 'Previous Photo',
                    onPressed: () {
                      _pageController.previousPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                      );
                      _onPageChanged(_currentIndex - 1);
                    },
                  ),
                ),
              ),
            if (_currentIndex < images.length - 1)
              Positioned(
                right: 12,
                top: 0,
                bottom: 0,
                child: Center(
                  child: IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black54,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.chevron_right, size: 30),
                    tooltip: 'Next Photo',
                    onPressed: () {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                      );
                      _onPageChanged(_currentIndex + 1);
                    },
                  ),
                ),
              ),
          ],

          // Bottom instruction chip & page indicator
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (hasMultiple) ...[
                      const Icon(Icons.photo_library_outlined, size: 16, color: Colors.amberAccent),
                      const SizedBox(width: 6),
                      Text(
                        'Photo ${_currentIndex + 1} of ${images.length}  •  ',
                        style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                    const Icon(Icons.pinch_outlined, size: 16, color: Colors.white70),
                    const SizedBox(width: 6),
                    const Text(
                      'Pinch / Scroll to zoom',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
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
