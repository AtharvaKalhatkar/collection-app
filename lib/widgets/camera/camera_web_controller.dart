// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

class WebCameraHelper {
  static int _nextViewId = 0;

  html.VideoElement? _videoElement;
  html.MediaStream? _stream;
  String? _viewTypeId;
  bool _isFrontCamera = false;
  bool _isReady = false;

  bool _hasTorch = false;
  bool _isTorchOn = false;
  String _flashMode = 'off'; // 'off', 'on', 'auto'

  bool get isReady => _isReady;
  bool get isFrontCamera => _isFrontCamera;
  bool get hasTorch => _hasTorch;
  bool get isTorchOn => _isTorchOn;
  String get flashMode => _flashMode;

  Future<void> initialize({bool frontCamera = false}) async {
    _isFrontCamera = frontCamera;
    _stopStream();

    _viewTypeId = 'web-bill-camera-${_nextViewId++}';

    _videoElement = html.VideoElement()
      ..autoplay = true
      ..muted = true
      ..setAttribute('playsinline', 'true')
      ..setAttribute('webkit-playsinline', 'true')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover';

    ui_web.platformViewRegistry.registerViewFactory(
      _viewTypeId!,
      (int id) => _videoElement!,
    );

    final facingMode = _isFrontCamera ? 'user' : 'environment';

    try {
      final mediaDevices = html.window.navigator.mediaDevices;
      if (mediaDevices == null) {
        throw Exception('Camera API (mediaDevices) not available on this browser/context');
      }

      // Request maximum camera resolution (4K/1080p) for ultra-sharp bill text
      try {
        _stream = await mediaDevices.getUserMedia({
          'video': {
            'facingMode': {'ideal': facingMode},
            'width': {'ideal': 3840, 'min': 1920},
            'height': {'ideal': 2160, 'min': 1080},
          },
          'audio': false,
        });
      } catch (_) {
        // Fallback to standard facingMode constraints if device rejects high-res params
        _stream = await mediaDevices.getUserMedia({
          'video': {'facingMode': {'ideal': facingMode}},
          'audio': false,
        });
      }

      _videoElement!.srcObject = _stream;
      await _videoElement!.play();
      _isReady = true;
      _detectTorch();

      // If user had flash enabled, turn torch back on
      if (_flashMode == 'on') {
        await setTorch(true);
      }
    } catch (e) {
      _stopStream();
      _isReady = false;
      rethrow;
    }
  }

  void _detectTorch() {
    _hasTorch = false;
    if (_stream == null) return;
    final tracks = _stream!.getVideoTracks();
    if (tracks.isEmpty) return;
    final track = tracks.first;

    try {
      final trackJs = js.JsObject.fromBrowserObject(track);
      if (trackJs.hasProperty('getCapabilities')) {
        final caps = trackJs.callMethod('getCapabilities');
        if (caps != null && caps is js.JsObject && caps.hasProperty('torch')) {
          _hasTorch = caps['torch'] == true;
        }
      }
    } catch (_) {}
  }

  Future<void> setTorch(bool on) async {
    _isTorchOn = on;
    if (_stream == null) return;
    final tracks = _stream!.getVideoTracks();
    if (tracks.isEmpty) return;
    final track = tracks.first;

    try {
      final trackJs = js.JsObject.fromBrowserObject(track);
      if (trackJs.hasProperty('applyConstraints')) {
        final advanced = js.JsObject.jsify([
          {'torch': on}
        ]);
        final constraints = js.JsObject.jsify({
          'advanced': advanced,
        });
        trackJs.callMethod('applyConstraints', [constraints]);
      }
    } catch (_) {}
  }

  Future<void> cycleFlashMode() async {
    if (_flashMode == 'off') {
      _flashMode = 'on';
      await setTorch(true);
    } else if (_flashMode == 'on') {
      _flashMode = 'auto';
      await setTorch(false);
    } else {
      _flashMode = 'off';
      await setTorch(false);
    }
  }

  Future<void> flipCamera() async {
    // When flipping to front camera, turn off torch
    if (_isTorchOn) {
      await setTorch(false);
    }
    await initialize(frontCamera: !_isFrontCamera);
  }

  Future<String?> capturePhotoBase64() async {
    if (_stream == null || !_isReady) return null;

    final needTemporaryFlash = (_flashMode == 'auto' || _flashMode == 'on') && !_isTorchOn;
    if (needTemporaryFlash) {
      await setTorch(true);
      await Future.delayed(const Duration(milliseconds: 150));
    }

    String? photoBase64;

    // 1. Try Hardware ImageCapture API first (delivers authentic 12MP/48MP full sensor HD JPEG)
    try {
      final tracks = _stream!.getVideoTracks();
      if (tracks.isNotEmpty) {
        final track = tracks.first;
        final trackJs = js.JsObject.fromBrowserObject(track);
        final imageCaptureConstructor = js.context['ImageCapture'];
        if (imageCaptureConstructor != null) {
          final capturer = js.JsObject(imageCaptureConstructor, [trackJs]);
          if (capturer.hasProperty('takePhoto')) {
            final completer = Completer<String?>();
            final promise = capturer.callMethod('takePhoto');
            promise.callMethod('then', [
              (blob) {
                try {
                  final reader = html.FileReader();
                  reader.readAsDataUrl(blob as html.Blob);
                  reader.onLoadEnd.first.then((_) {
                    final dataUrl = reader.result as String?;
                    if (dataUrl != null && dataUrl.contains(',')) {
                      completer.complete(dataUrl.split(',').last);
                    } else {
                      completer.complete(null);
                    }
                  });
                } catch (_) {
                  completer.complete(null);
                }
              },
              (err) {
                completer.complete(null);
              }
            ]);
            photoBase64 = await completer.future.timeout(
              const Duration(seconds: 2),
              onTimeout: () => null,
            );
          }
        }
      }
    } catch (_) {}

    // 2. High-Resolution Canvas fallback if ImageCapture isn't supported
    if (photoBase64 == null && _videoElement != null) {
      final width = _videoElement!.videoWidth;
      final height = _videoElement!.videoHeight;
      if (width > 0 && height > 0) {
        final canvas = html.CanvasElement(width: width, height: height);
        final ctx = canvas.context2D;

        if (_isFrontCamera) {
          // Mirror front camera photo so text isn't reversed
          ctx.translate(width, 0);
          ctx.scale(-1, 1);
        }

        ctx.drawImage(_videoElement!, 0, 0);

        // High quality JPEG (0.95 preserves ultra-sharp text and numbers)
        final dataUrl = canvas.toDataUrl('image/jpeg', 0.95);
        photoBase64 = dataUrl.split(',').last;
      }
    }

    if (needTemporaryFlash) {
      await setTorch(false);
    }

    return photoBase64;
  }

  Widget buildPreview() {
    if (_viewTypeId == null || !_isReady) {
      return Container(color: Colors.black);
    }
    return HtmlElementView(viewType: _viewTypeId!);
  }

  void _stopStream() {
    if (_stream != null) {
      for (final track in _stream!.getTracks()) {
        track.stop();
      }
      _stream = null;
    }
    if (_videoElement != null) {
      _videoElement!.srcObject = null;
    }
    _isTorchOn = false;
    _isReady = false;
  }

  void dispose() {
    _stopStream();
  }
}
