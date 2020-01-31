import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_ffmpeg/flutter_ffmpeg.dart';

typedef void ProgressStreamInitCallback(Stream<double> progressStream);
typedef void ProgressCallback(double progress);

class VideoProcessSettings {
  final Duration start;
  final Duration end;
  final double speed;
  final String text;

  VideoProcessSettings({this.start, this.end, this.speed, this.text});

  get asMap =>
      {'start': start?.inMilliseconds, 'end': end?.inMilliseconds, 'speed': speed, 'text': text};
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
          if (progress < 0.0 || progress >= 1.0) _taskProgressControllers.remove(taskId).close();
        }
      });
    }
    return _taskProgressControllers;
  }

  static Stream<double> progressStream({taskId: String}) =>
      taskProgressControllers[taskId]?.stream;

  static Future<String> processVideo(
      {String inputPath,
      String outputPath,
      List<VideoProcessSettings> settings,
      ProgressStreamInitCallback onProgressStreamInitialized}) {
    onProgressStreamInitialized ??= (_) {};
    final taskId = outputPath;
    if (taskProgressControllers[taskId] != null) {
      onProgressStreamInitialized(progressStream(taskId: taskId));
      return Future.value(taskId);
    }
    taskProgressControllers[taskId] = StreamController.broadcast();
    onProgressStreamInitialized(progressStream(taskId: taskId));
    final settingsMap = settings.map((s) => s.asMap).toList();
    //return _channel.invokeMethod('processVideo', [inputPath, outputPath, settingsMap]);
    return _processVideoFFMPEG(inputPath: inputPath, outputPath: outputPath, settings: settings);
  }

  static Future<String> processVideoWithOverlay(
      {String inputPath,
      String outputPath,
      List<VideoProcessSettings> settings,
      ProgressStreamInitCallback onProgressStreamInitialized}) {
    onProgressStreamInitialized ??= (_) {};
    final taskId = outputPath;
    if (taskProgressControllers[taskId] != null) {
      onProgressStreamInitialized(progressStream(taskId: taskId));
      return Future.value(taskId);
    }
    taskProgressControllers[taskId] = StreamController.broadcast();
    onProgressStreamInitialized(progressStream(taskId: taskId));
    final settingsMap = settings.map((s) => s.asMap).toList();
    return _channel.invokeMethod('processVideoWithOverlay', [inputPath, outputPath, settingsMap]);
  }

  static Future<String> _processVideoFFMPEG(
      {String inputPath, String outputPath, List<VideoProcessSettings> settings}) async {
//    var args = [
//      "-i",
//      '$inputPath',
//      '-filter:v',
//      'setpts=${1.0 / 4.0}*PTS',
//      '-an',
//      '$outputPath'
//    ];
//    var args = [
//      '-itsscale',
//      '${1.0 / 4.0}',
//      "-i",
//      '$inputPath',
//      '-c',
//      'copy',
//      '$outputPath'
//    ];
//    await FlutterFFmpeg().executeWithArguments(args);
//    await File(inputPath).delete();
//    await File(outputPath).rename(inputPath);

    //TODO: Change settings into ffmpeg command

    var args = [
      "-i",
      '$inputPath',
      '-filter_complex',
      '[0:v]trim=0:10,setpts=PTS-STARTPTS[v1]; [0:v]trim=10:50,setpts=0.25*(PTS-STARTPTS)[v2]; [0:v]trim=50,setpts=PTS-STARTPTS[v3]; [0:a]atrim=0:10,asetpts=PTS-STARTPTS[a1]; [0:a]atrim=10:50,asetpts=PTS-STARTPTS,atempo=4[a2]; [0:a]atrim=50,asetpts=PTS-STARTPTS[a3]; [v1][a1][v2][a2][v3][a3]concat=n=3:v=1:a=1',
//      '-preset',
//      'ultrafast',
//      '-profile:v',
//      'baseline',
      '$outputPath',
    ];

    await FlutterFFmpeg().executeWithArguments(args);
    return outputPath;
  }
}
