import 'dart:async';

import 'package:flutter/services.dart';

class VideoManipulation {
  static const MethodChannel _channel =
      const MethodChannel('video_manipulation');

  static Future<String> get platformVersion async {
    final String version = await _channel.invokeMethod('getPlatformVersion');
    return version;
  }
}
