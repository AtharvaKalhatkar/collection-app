import 'package:flutter/material.dart';
import '../utils/image_compress_helper.dart';

/// Full-screen zoomable image viewer supporting pinch-to-zoom, scroll-zoom,
/// pan gestures, and manual zoom controls.
class FullScreenImageViewer extends StatefulWidget {
  final String imageBase64;
  final String title;
  final String? subtitle;

  const FullScreenImageViewer({
    super.key,
    required this.imageBase64,
    required this.title,
    this.subtitle,
  });

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  final TransformationController _transformationController = TransformationController();
  double _currentScale = 1.0;

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    final imageBytes = ImageCompressHelper.safeBase64Decode(widget.imageBase64);

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
              widget.title,
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
          // Interactive Pan / Pinch / Zoom Viewer
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

          // Bottom instruction chip
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
                  children: const [
                    Icon(Icons.pinch_outlined, size: 16, color: Colors.white70),
                    SizedBox(width: 8),
                    Text(
                      'Pinch / Scroll to zoom • Drag to pan',
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
