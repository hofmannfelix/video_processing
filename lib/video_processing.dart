import 'dart:async';

import 'package:flutter/services.dart';

typedef void ProgressCallback(double progress);

class VideoProcessing {
  static const MethodChannel _channel = const MethodChannel('video_processing');

  static StreamController<double> _progressController;

  static Stream<double> get progressStream {
    if (_progressController == null) {
      _progressController = StreamController.broadcast();
      _channel.setMethodCallHandler((MethodCall call) async {
        if (call.method == 'updateProgress') {
          double progress = call.arguments['progress'] ?? 0.0;
          _progressController.add(progress);
        }
      });
    }
    return _progressController.stream;
  }

  static Future<String> generateVideo(
      List<String> paths, String filename, int fps, double speed) async {
    return await _channel.invokeMethod('generateVideo', [paths, filename, fps, speed]);
  }
}
