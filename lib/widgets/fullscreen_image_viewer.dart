import 'package:flutter/material.dart';
import '../utils/image_compress_helper.dart';
import '../utils/image_share_helper.dart';

/// Full-screen zoomable image viewer supporting single or multiple images,
/// pinch-to-zoom, double-tap zoom, smooth pan gestures, and multi-page navigation.
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
  late PageController _pageController;
  late int _currentIndex;

  // Zoom state notifier to prevent rebuilding the full widget tree on pinch gestures
  final ValueNotifier<bool> _isZoomedNotifier = ValueNotifier<bool>(false);

  // References to page zoom controllers to trigger zoom reset when page changes
  final Map<int, _ZoomableImagePageState> _pageStates = {};

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
    final total = _images.length;
    _currentIndex = total > 0 ? widget.initialIndex.clamp(0, total - 1) : 0;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _isZoomedNotifier.dispose();
    super.dispose();
  }

  void _registerPageState(int index, _ZoomableImagePageState state) {
    _pageStates[index] = state;
  }

  void _unregisterPageState(int index) {
    _pageStates.remove(index);
  }

  void _onScaleChanged(double scale) {
    final isZoomed = scale > 1.05;
    if (_isZoomedNotifier.value != isZoomed) {
      _isZoomedNotifier.value = isZoomed;
    }
  }

  void _resetCurrentZoom() {
    _pageStates[_currentIndex]?.resetZoom();
    _isZoomedNotifier.value = false;
  }

  void _goToPrevious() {
    if (_currentIndex > 0) {
      _resetCurrentZoom();
      final prevIdx = _currentIndex - 1;
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          prevIdx,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOutCubic,
        );
      } else {
        setState(() => _currentIndex = prevIdx);
      }
    }
  }

  void _goToNext() {
    if (_currentIndex < _images.length - 1) {
      _resetCurrentZoom();
      final nextIdx = _currentIndex + 1;
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          nextIdx,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInOutCubic,
        );
      } else {
        setState(() => _currentIndex = nextIdx);
      }
    }
  }

  void _onPageChanged(int index) {
    _resetCurrentZoom();
    setState(() {
      _currentIndex = index;
    });
  }

  Future<void> _shareCurrentImage() async {
    final images = _images;
    if (images.isEmpty || _currentIndex >= images.length) return;
    final b64 = images[_currentIndex];
    final bytes = ImageCompressHelper.safeBase64Decode(b64);
    if (bytes == null) return;

    final sanitizedTitle = widget.title.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final filename = '${sanitizedTitle}_${_currentIndex + 1}.jpg';

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sharing photo...'),
          duration: Duration(milliseconds: 1000),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    await ImageShareHelper.shareOrDownloadImage(
      bytes,
      filename: filename,
      title: widget.title,
    );
  }

  @override
  Widget build(BuildContext context) {
    final images = _images;
    final hasMultiple = images.length > 1;

    final displayTitle = hasMultiple
        ? '${widget.title} (${_currentIndex + 1}/${images.length})'
        : widget.title;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0F1D),
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.75),
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
          IconButton(
            icon: const Icon(Icons.share_outlined, size: 22, color: Colors.white),
            tooltip: 'Share via WhatsApp',
            onPressed: _shareCurrentImage,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. PAGEVIEW FOR MULTI-PHOTO SWIPING
          if (images.isEmpty)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.broken_image, size: 54, color: Colors.white54),
                  SizedBox(height: 12),
                  Text('No image data available', style: TextStyle(color: Colors.white70)),
                ],
              ),
            )
          else if (images.length == 1)
            _ZoomableImagePage(
              key: const ValueKey('zoom-single-page'),
              imageBase64: images.first,
              onScaleChanged: (_) {},
              onStateCreated: (state) => _registerPageState(0, state),
              onStateDisposed: () => _unregisterPageState(0),
            )
          else
            ValueListenableBuilder<bool>(
              valueListenable: _isZoomedNotifier,
              builder: (context, isZoomed, _) {
                return PageView.builder(
                  controller: _pageController,
                  physics: isZoomed
                      ? const NeverScrollableScrollPhysics() // When zoomed, panning pans image rather than swiping page
                      : const BouncingScrollPhysics(),
                  itemCount: images.length,
                  onPageChanged: _onPageChanged,
                  itemBuilder: (context, index) {
                    return _ZoomableImagePage(
                      key: ValueKey('zoom-page-$index'),
                      imageBase64: images[index],
                      onScaleChanged: (scale) {
                        if (_currentIndex == index) {
                          _onScaleChanged(scale);
                        }
                      },
                      onStateCreated: (state) => _registerPageState(index, state),
                      onStateDisposed: () => _unregisterPageState(index),
                    );
                  },
                );
              },
            ),

          // 2. PREVIOUS BUTTON (Left arrow)
          if (hasMultiple && _currentIndex > 0)
            Positioned(
              left: 14,
              top: 0,
              bottom: 0,
              child: Center(
                child: Material(
                  color: Colors.black.withValues(alpha: 0.65),
                  shape: const CircleBorder(),
                  elevation: 6,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _goToPrevious,
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white38, width: 1.2),
                      ),
                      child: const Icon(
                        Icons.chevron_left_rounded,
                        size: 36,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // 3. NEXT BUTTON (Right arrow)
          if (hasMultiple && _currentIndex < images.length - 1)
            Positioned(
              right: 14,
              top: 0,
              bottom: 0,
              child: Center(
                child: Material(
                  color: Colors.black.withValues(alpha: 0.65),
                  shape: const CircleBorder(),
                  elevation: 6,
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: _goToNext,
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white38, width: 1.2),
                      ),
                      child: const Icon(
                        Icons.chevron_right_rounded,
                        size: 36,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // 4. BOTTOM INDICATOR & CONTROLS
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Multi-page dots indicator if multiple photos
                if (hasMultiple)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(images.length, (i) {
                        final isActive = i == _currentIndex;
                        return GestureDetector(
                          onTap: () {
                            if (i != _currentIndex) {
                              _resetCurrentZoom();
                              _pageController.animateToPage(
                                i,
                                duration: const Duration(milliseconds: 280),
                                curve: Curves.easeInOutCubic,
                              );
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: isActive ? 18 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: isActive ? Colors.amberAccent : Colors.white38,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),

                // Hint chip
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasMultiple) ...[
                        const Icon(Icons.photo_library_outlined, size: 14, color: Colors.amberAccent),
                        const SizedBox(width: 6),
                        Text(
                          '${_currentIndex + 1}/${images.length}',
                          style: const TextStyle(color: Colors.amberAccent, fontSize: 11.5, fontWeight: FontWeight.bold),
                        ),
                        const Text(
                          ' • ',
                          style: TextStyle(color: Colors.white38, fontSize: 11.5),
                        ),
                      ],
                      const Icon(Icons.touch_app_outlined, size: 14, color: Colors.white70),
                      const SizedBox(width: 5),
                      const Text(
                        'Double-tap or pinch to zoom',
                        style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Dedicated single-page zoomable image container.
/// Encapsulates its own TransformationController and AnimationController to ensure 60fps
/// smooth panning, double-tap zoom, and pinch gestures without causing rebuilds of the parent widget tree.
class _ZoomableImagePage extends StatefulWidget {
  final String imageBase64;
  final ValueChanged<double> onScaleChanged;
  final void Function(_ZoomableImagePageState state) onStateCreated;
  final VoidCallback onStateDisposed;

  const _ZoomableImagePage({
    super.key,
    required this.imageBase64,
    required this.onScaleChanged,
    required this.onStateCreated,
    required this.onStateDisposed,
  });

  @override
  State<_ZoomableImagePage> createState() => _ZoomableImagePageState();
}

class _ZoomableImagePageState extends State<_ZoomableImagePage>
    with SingleTickerProviderStateMixin {
  final TransformationController _controller = TransformationController();
  late AnimationController _animController;
  Animation<Matrix4>? _anim;

  Offset _doubleTapPosition = Offset.zero;

  @override
  void initState() {
    super.initState();
    widget.onStateCreated(this);
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

  }

  @override
  void dispose() {
    widget.onStateDisposed();
    _controller.dispose();
    _animController.dispose();
    super.dispose();
  }

  void resetZoom() {
    _animateToMatrix(Matrix4.identity());
    widget.onScaleChanged(1.0);
  }

  void _animateToMatrix(Matrix4 target) {
    _animController.stop();
    final start = _controller.value;
    _anim = Matrix4Tween(begin: start, end: target).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _anim!.addListener(() {
      _controller.value = _anim!.value;
    });
    _animController.forward(from: 0.0);
  }

  void _handleDoubleTap() {
    final currentScale = _controller.value.getMaxScaleOnAxis();
    if (currentScale > 1.15) {
      // Already zoomed in -> smoothly reset to 1.0x
      _animateToMatrix(Matrix4.identity());
      widget.onScaleChanged(1.0);
    } else {
      // Zoom into tapped point at 2.5x smoothly
      const targetScale = 2.5;
      final x = -_doubleTapPosition.dx * (targetScale - 1);
      final y = -_doubleTapPosition.dy * (targetScale - 1);
      final target = Matrix4.identity()
        ..storage[0] = targetScale
        ..storage[5] = targetScale
        ..storage[12] = x
        ..storage[13] = y;
      _animateToMatrix(target);
      widget.onScaleChanged(targetScale);
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageBytes = ImageCompressHelper.safeBase64Decode(widget.imageBase64);

    if (imageBytes == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image, size: 54, color: Colors.white54),
            SizedBox(height: 12),
            Text('Could not decode image', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onDoubleTapDown: (details) {
        _doubleTapPosition = details.localPosition;
      },
      onDoubleTap: _handleDoubleTap,
      child: Center(
        child: InteractiveViewer(
          transformationController: _controller,
          minScale: 1.0,
          maxScale: 6.0,
          panEnabled: true,
          scaleEnabled: true,
          clipBehavior: Clip.none,
          boundaryMargin: EdgeInsets.zero,
          onInteractionEnd: (_) {
            final scale = _controller.value.getMaxScaleOnAxis();
            widget.onScaleChanged(scale);
          },
          child: Image.memory(
            imageBytes,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            errorBuilder: (context, error, stackTrace) {
              return const Center(
                child: Text('Could not render image', style: TextStyle(color: Colors.white)),
              );
            },
          ),
        ),
      ),
    );
  }
}
