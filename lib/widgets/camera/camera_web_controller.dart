// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:flutter/material.dart';

class WebCameraHelper {
  static int _nextViewId = 0;

  html.VideoElement? _videoElement;
  html.MediaStream? _stream;
  String? _viewTypeId;
  bool _isFrontCamera = false;
  bool _isReady = false;

  bool get isReady => _isReady;
  bool get isFrontCamera => _isFrontCamera;

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

      _stream = await mediaDevices.getUserMedia({
        'video': {
          'facingMode': {'ideal': facingMode},
          'width': {'ideal': 1920},
          'height': {'ideal': 1080},
        },
        'audio': false,
      });

      _videoElement!.srcObject = _stream;
      await _videoElement!.play();
      _isReady = true;
    } catch (e) {
      _stopStream();
      _isReady = false;
      rethrow;
    }
  }

  Future<void> flipCamera() async {
    await initialize(frontCamera: !_isFrontCamera);
  }

  Future<String?> capturePhotoBase64() async {
    if (_videoElement == null || !_isReady) return null;

    final width = _videoElement!.videoWidth;
    final height = _videoElement!.videoHeight;
    if (width <= 0 || height <= 0) return null;

    final canvas = html.CanvasElement(width: width, height: height);
    final ctx = canvas.context2D;

    if (_isFrontCamera) {
      // Mirror front camera photo so text isn't reversed
      ctx.translate(width, 0);
      ctx.scale(-1, 1);
    }

    ctx.drawImage(_videoElement!, 0, 0);

    // High quality JPEG (0.92 preserves ultra-sharp text and numbers)
    final dataUrl = canvas.toDataUrl('image/jpeg', 0.92);
    final clean = dataUrl.split(',').last;
    return clean;
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
    _isReady = false;
  }

  void dispose() {
    _stopStream();
  }
}
