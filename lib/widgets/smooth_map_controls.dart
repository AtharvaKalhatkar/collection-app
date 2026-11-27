import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Shared map interaction settings tuned for mobile touchscreens & web:
/// - Disables 2-finger rotation so pinch-zoom never spins the map sideways.
/// - Disables the gesture race lockout so pinch-zoom responds immediately.
/// - Enables double-tap-and-drag 1-finger zoom for easy one-handed use.
const InteractionOptions kSmoothMapInteractionOptions = InteractionOptions(
  flags: InteractiveFlag.drag |
      InteractiveFlag.pinchZoom |
      InteractiveFlag.pinchMove |
      InteractiveFlag.doubleTapZoom |
      InteractiveFlag.doubleTapDragZoom |
      InteractiveFlag.scrollWheelZoom |
      InteractiveFlag.flingAnimation,
  enableMultiFingerGestureRace: false,
  pinchZoomThreshold: 0.1,
  pinchMoveThreshold: 12.0,
  scrollWheelVelocity: 0.005,
  flingAnimationDampingRatio: 6.0,
);

/// Shared multi-subdomain Google tile layer with generous buffer & smooth fade-in
/// so panning and zooming stay smooth without rate-limit flicker.
TileLayer buildSmoothMapTileLayer({
  required bool isSatellite,
  double maxZoom = 20.0,
}) {
  return TileLayer(
    key: ValueKey('google_tile_${isSatellite ? 'sat' : 'road'}'),
    urlTemplate: isSatellite
        ? 'https://{s}.google.com/vt/lyrs=y&x={x}&y={y}&z={z}'
        : 'https://{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
    subdomains: const ['mt0', 'mt1', 'mt2', 'mt3'],
    userAgentPackageName: 'com.purva.dailycollection',
    minZoom: 0,
    maxZoom: maxZoom,
    maxNativeZoom: 20,
    keepBuffer: 4,
    panBuffer: 1,
    tileDisplay: const TileDisplay.fadeIn(
      duration: Duration(milliseconds: 120),
    ),
    evictErrorTileStrategy: EvictErrorTileStrategy.dispose,
  );
}

final Expando<AnimationController> _activeMapAnimations =
    Expando<AnimationController>('active_map_anim');

/// Cancels and disposes any in-flight camera animation for [controller].
/// Call from `State.dispose()` before disposing [controller].
void cancelSmoothMapAnimation(MapController controller) {
  final prev = _activeMapAnimations[controller];
  if (prev != null) {
    _activeMapAnimations[controller] = null;
    prev.stop();
    prev.dispose();
  }
}

/// Smoothly animates a [MapController] to [destLocation] and [destZoom].
void smoothAnimatedMapMove({
  required MapController controller,
  required TickerProvider vsync,
  required LatLng destLocation,
  required double destZoom,
  double minZoom = 5.0,
  double maxZoom = 20.0,
}) {
  cancelSmoothMapAnimation(controller);
  final targetZoom = destZoom.clamp(minZoom, maxZoom);
  LatLng startCenter;
  double startZoom;
  try {
    startCenter = controller.camera.center;
    startZoom = controller.camera.zoom;
  } catch (_) {
    try {
      controller.move(destLocation, targetZoom);
    } catch (_) {}
    return;
  }

  final latTween = Tween<double>(begin: startCenter.latitude, end: destLocation.latitude);
  final lngTween = Tween<double>(begin: startCenter.longitude, end: destLocation.longitude);
  final zoomTween = Tween<double>(begin: startZoom, end: targetZoom);

  final animController = AnimationController(
    duration: const Duration(milliseconds: 240),
    vsync: vsync,
  );
  _activeMapAnimations[controller] = animController;
  final animation = CurvedAnimation(parent: animController, curve: Curves.easeOutCubic);

  animController.addListener(() {
    try {
      controller.move(
        LatLng(latTween.evaluate(animation), lngTween.evaluate(animation)),
        zoomTween.evaluate(animation),
      );
    } catch (_) {}
  });

  animController.addStatusListener((status) {
    if (status == AnimationStatus.completed || status == AnimationStatus.dismissed) {
      if (identical(_activeMapAnimations[controller], animController)) {
        _activeMapAnimations[controller] = null;
      }
      animation.dispose();
      animController.dispose();
    }
  });

  animController.forward();
}

/// Smoothly steps the current map zoom level by [deltaZoom] (e.g. +1.0 or -1.0).
void smoothStepMapZoom({
  required MapController controller,
  required TickerProvider vsync,
  required double deltaZoom,
  double minZoom = 5.0,
  double maxZoom = 20.0,
}) {
  try {
    final cam = controller.camera;
    smoothAnimatedMapMove(
      controller: controller,
      vsync: vsync,
      destLocation: cam.center,
      destZoom: (cam.zoom + deltaZoom).clamp(minZoom, maxZoom),
      minZoom: minZoom,
      maxZoom: maxZoom,
    );
  } catch (_) {}
}

/// Sleek Google-Maps-style `+` / `-` zoom rocker pill for one-handed mobile use.
class MapZoomControlPill extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final bool horizontal;

  const MapZoomControlPill({
    super.key,
    required this.onZoomIn,
    required this.onZoomOut,
    this.horizontal = false,
  });

  @override
  Widget build(BuildContext context) {
    final zoomInBtn = Tooltip(
      message: 'Zoom In',
      child: InkWell(
        onTap: onZoomIn,
        borderRadius: horizontal
            ? const BorderRadius.horizontal(right: Radius.circular(12))
            : const BorderRadius.vertical(top: Radius.circular(12)),
        child: const SizedBox(
          width: 40,
          height: 38,
          child: Icon(Icons.add_rounded, size: 20, color: Color(0xFF0F172A)),
        ),
      ),
    );
    final zoomOutBtn = Tooltip(
      message: 'Zoom Out',
      child: InkWell(
        onTap: onZoomOut,
        borderRadius: horizontal
            ? const BorderRadius.horizontal(left: Radius.circular(12))
            : const BorderRadius.vertical(bottom: Radius.circular(12)),
        child: const SizedBox(
          width: 40,
          height: 38,
          child: Icon(Icons.remove_rounded, size: 20, color: Color(0xFF0F172A)),
        ),
      ),
    );

    return Material(
      elevation: 3,
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: horizontal
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                zoomOutBtn,
                Container(width: 1, height: 24, color: const Color(0xFFE2E8F0)),
                zoomInBtn,
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                zoomInBtn,
                Container(width: 24, height: 1, color: const Color(0xFFE2E8F0)),
                zoomOutBtn,
              ],
            ),
    );
  }
}
