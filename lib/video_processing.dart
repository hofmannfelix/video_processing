import 'dart:async';

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
      ProgressStreamInitCallback onProgressStreamInitialized}) async {
    onProgressStreamInitialized ??= (_) {};
    final taskId = outputPath;
    if (taskProgressControllers[taskId] != null) {
      onProgressStreamInitialized(progressStream(taskId: taskId));
      return Future.value(taskId);
    }
    taskProgressControllers[taskId] = StreamController.broadcast();
    onProgressStreamInitialized(progressStream(taskId: taskId));
    //final settingsMap = settings.reversed.map((s) => s.asMap).toList();
    //return _channel.invokeMethod('processVideo', [inputPath, outputPath, settingsMap]);
    final result = await _processVideoFFMPEG(
        inputPath: inputPath, outputPath: outputPath, settings: settings);
    _taskProgressControllers.remove(taskId).close();
    return result;
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
    String filterInput = "";

    ///Video settings
    for (int i = 0; i < settings.length; i++) {
      final s = settings[i];
      final start = (s.start.inMilliseconds / 1000).toStringAsFixed(3);
      final end = (s.end.inMilliseconds / 1000).toStringAsFixed(3);
      final speed = (1 / s.speed).toStringAsFixed(3);
      filterInput += "[0:v]trim=$start:$end,setpts=$speed*(PTS-STARTPTS)[v${i + 1}];";
    }

    ///Audio settings
    for (int i = 0; i < settings.length; i++) {
      final s = settings[i];
      final start = (s.start.inMilliseconds / 1000).toStringAsFixed(3);
      final end = (s.end.inMilliseconds / 1000).toStringAsFixed(3);
      final speed = (s.speed).toStringAsFixed(3);
      filterInput += "[0:a]atrim=$start:$end,asetpts=PTS-STARTPTS,atempo=$speed[a${i + 1}];";
    }

    ///Merge settings
    for (int i = 1; i <= settings.length; i++) {
      filterInput += "[v$i][a$i]";
    }
    filterInput += "concat=n=${settings.length}:v=1:a=1";

    ///Init progress callback
    var timelapseDuration = Duration.zero;
    for (final s in settings) timelapseDuration += (s.end - s.start) * (1 / s.speed);
    final ffmpegConfig = FlutterFFmpegConfig();
    ffmpegConfig.resetStatistics();
    ffmpegConfig.enableStatisticsCallback((int time, int size, double bitrate, double speed,
        int videoFrameNumber, double videoQuality, double videoFps) {
      final taskId = outputPath;
      final progress = (time / timelapseDuration.inMilliseconds).clamp(0.0, 1.0);
      _taskProgressControllers[taskId].add(progress);
    });

    ///Execute ffmpeg
    final returnCode = await FlutterFFmpeg().executeWithArguments([
      "-i",
      '$inputPath',
      '-filter_complex',
      '$filterInput',
      //'[0:v]trim=0:10,setpts=PTS-STARTPTS[v1]; [0:v]trim=10:50,setpts=0.25*(PTS-STARTPTS)[v2]; [0:v]trim=50,setpts=PTS-STARTPTS[v3]; [0:a]atrim=0:10,asetpts=PTS-STARTPTS[a1]; [0:a]atrim=10:50,asetpts=PTS-STARTPTS,atempo=4[a2]; [0:a]atrim=50,asetpts=PTS-STARTPTS[a3]; [v1][a1][v2][a2][v3][a3]concat=n=3:v=1:a=1',
      '-preset',
      'superfast',
      '-crf',
      '30',
      '-profile:v',
      'baseline',
      '$outputPath',
    ]);
    if (returnCode != 0) {
      final lastStats = await ffmpegConfig.getLastReceivedStatistics();
      throw ArgumentError.value(
        inputPath,
        "FFmpeg Error",
        "Could not process file at given path: $lastStats",
      );
    }
    return outputPath;
  }
}

//TODO: Change settings into ffmpeg command
//    final s = """
//    [0:v]trim=0:10,setpts=PTS-STARTPTS[v1];
//    [0:v]trim=10:50,setpts=0.25*(PTS-STARTPTS)[v2];
//    [0:v]trim=50,setpts=PTS-STARTPTS[v3];
//    [0:a]atrim=0:10,asetpts=PTS-STARTPTS[a1];
//    [0:a]atrim=10:50,asetpts=PTS-STARTPTS,atempo=4[a2];
//    [0:a]atrim=50,asetpts=PTS-STARTPTS[a3];
//    [v1][a1][v2][a2][v3][a3]concat=n=3:v=1:a=1,
//    """;
