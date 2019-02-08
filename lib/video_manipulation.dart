import 'dart:async';

import 'package:flutter/services.dart';

class VideoManipulation {
  static const MethodChannel _channel =
      const MethodChannel('video_manipulation');

  static Future<String> get platformVersion async {
    final String version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }

  static Future<String> generateVideo(List<String> paths, String filename, int fps, double speed) async {
    return await _channel.invokeMethod('generateVideo', [paths, filename, fps, speed]);
  }
}
