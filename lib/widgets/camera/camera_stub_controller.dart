import 'package:flutter/material.dart';

class WebCameraHelper {
  bool get isReady => false;
  bool get isFrontCamera => false;
  bool get hasTorch => false;
  bool get isTorchOn => false;
  String get flashMode => 'off';

  Future<void> initialize({bool frontCamera = false}) async {
    throw UnsupportedError('In-app WebRTC camera is only supported on Web browsers.');
  }

  Future<void> cycleFlashMode() async {}

  Future<void> setTorch(bool on) async {}

  Future<void> flipCamera() async {}

  Future<String?> capturePhotoBase64() async {
    return null;
  }

  Widget buildPreview() {
    return Container(color: Colors.black);
  }

  void dispose() {}
}
