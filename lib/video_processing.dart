import 'dart:async';

import 'package:flutter/services.dart';

typedef void ProgressCallback(double progress);

class VideoProcessSettings {
  final Duration start;
  final Duration end;
  final double speed;

  VideoProcessSettings({this.start, this.end, this.speed});

  get asMap => {'start': start.inMilliseconds, 'end': end.inMilliseconds, 'speed': speed};
}

class VideoProcessing {
  static const MethodChannel _channel = const MethodChannel('video_processing');

  static Map<String, StreamController<double>> _taskProgressControllers;

  static Map<String, StreamController<double>> get taskProgressControllers {
    if (_taskProgressControllers == null) {
      _taskProgressControllers = {};
      _channel.setMethodCallHandler((MethodCall call) async {
        if (call.method == 'updateProgress') {
          String taskId = call.arguments['taskId'];
          double progress = call.arguments['progress'] ?? 0.0;
          _taskProgressControllers[taskId].add(progress);
          if (progress < 0.0 || progress >= 100.0)
            _taskProgressControllers.remove(taskId).close();
        }
      });
    }
    return _taskProgressControllers;
  }

  static Stream<double> progressStream({taskId: String}) =>
      taskProgressControllers[taskId]?.stream;

  static Future<String> processVideo(
      {String inputPath, String outputPath, List<VideoProcessSettings> settings}) async {
    final taskId = outputPath;
    if (taskProgressControllers[taskId] != null) return taskId;
    taskProgressControllers[taskId] = StreamController.broadcast();

    final settingsMap = settings.map((s) => s.asMap).toList();
    await _channel.invokeMethod('processVideo', [inputPath, outputPath, settingsMap]);
    return taskId;
  }

  @deprecated
  static Future<String> generateVideo(
      List<String> paths, String filename, int fps, double speed) async {
    return await _channel.invokeMethod('generateVideo', [paths, filename, fps, speed]);
  }
}
