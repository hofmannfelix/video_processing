import Flutter
import UIKit
import AVFoundation
import MobileCoreServices

public class VideoProcessSettings {
    final let start: Int64
    final var end: Int64
    final var speed: Double
    
    init(start: Int64, end: Int64, speed: Double) {
        self.start = start
        self.end = end
        self.speed = speed
    }
}

public class SwiftVideoProcessingPlugin: NSObject, FlutterPlugin {
    public static var _channel: FlutterMethodChannel?;
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        _channel = FlutterMethodChannel(name: "video_processing", binaryMessenger: registrar.messenger())
        let instance = SwiftVideoProcessingPlugin()
        registrar.addMethodCallDelegate(instance, channel: _channel!)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "processVideo" {
            if let args = call.arguments as? [AnyObject],
                let inputPath = args[0] as? String,
                let outputPath = args[1] as? String,
                let settingsMap = args[2] as? [[String: AnyObject]] {
                let settings = settingsMap.map({VideoProcessSettings(start: Int64($0["start"] as! Int), end: Int64($0["end"] as! Int), speed: $0["speed"] as? Double ?? 1.0)})
                
                //TODO: should be done by caller in flutter
                let inputFileURL = URL(fileURLWithPath: inputPath)
                let outputFileURL = URL(fileURLWithPath: outputPath)
                if FileManager.default.isDeletableFile(atPath: outputFileURL.relativePath) {
                    try? FileManager.default.removeItem(at: outputFileURL)
                }
                
                VSVideoSpeeder.shared.scaleAsset(inputUrl: inputFileURL, outputFileUrl: outputFileURL, settings: settings) { (exporter) in
                    if let exporter = exporter {
                        switch exporter.status {
                        case .failed:
                            print(exporter.error?.localizedDescription ?? "Error in exporting..")
                            //send error to progress method
                            break
                        case .completed:
                            print("Scaled video has been generated successfully!")
                            printFileSizeInMB(filePath: outputFileURL.relativePath)
                            result(outputFileURL.relativePath) //TODO: should return before calling export
                            break
                        case .unknown: break
                        case .waiting: break
                        case .exporting:
                            //TODO: status never called so set up timer that update progress with SwiftVideoProcessingPlugin.sendProgressForCurrentVideoProcess(progress: Double(exporter.progress))
                            break
                        case .cancelled: break
                        }
                    }
                    else {
                        print("Exporter is not initialized.")
                    }
                }
                
            } else {
                result(nil)
            }
        }
    }
    
    public static func sendProgressForCurrentVideoProcess(progress: Double) {
        _channel?.invokeMethod("updateProgress", arguments: ["progress": progress])
    }
}

class VSVideoSpeeder: NSObject {
    let MaxAudioSpeed = 20.0
    
    /// Singleton instance of `VSVideoSpeeder`
    static var shared: VSVideoSpeeder = {
        return VSVideoSpeeder()
    }()
    
    func scaleAsset(inputUrl: URL, outputFileUrl: URL, settings: [VideoProcessSettings], completion: @escaping (_ exporter: AVAssetExportSession?) -> Void) {
        let asset = AVAsset(url: inputUrl)
        let timeRange = CMTimeRangeMake(kCMTimeZero, asset.duration)
        let videoTracks = asset.tracks(withMediaType: AVMediaType.video)
        if videoTracks.isEmpty {
            completion(nil)
            return
        }
        do {
            /// Video track
            let videoTrack = videoTracks.first!
            let mixComposition = AVMutableComposition()
            let compositionVideoTrack = mixComposition.addMutableTrack(withMediaType: AVMediaType.video, preferredTrackID: kCMPersistentTrackID_Invalid)
            try compositionVideoTrack?.insertTimeRange(timeRange, of: videoTrack, at: kCMTimeZero)
            
            /// Audio Track
            let audioTracks = asset.tracks(withMediaType: AVMediaType.audio)
            let audioTrack = audioTracks.first
            var compositionAudioTrack: AVMutableCompositionTrack?
            if !audioTracks.isEmpty {
                compositionAudioTrack = mixComposition.addMutableTrack(withMediaType: AVMediaType.audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            }
            try? compositionAudioTrack?.insertTimeRange(timeRange, of: audioTrack!, at: kCMTimeZero)
            
            /// Get the scaled video duration
            settings.forEach({ settings in
                let sectionDuration = settings.end - settings.start
                var timeRange = CMTimeRangeMake(CMTimeMake(settings.start, 1000), CMTimeMake(sectionDuration, 1000))
                let scaledDuration = CMTimeMake(Int64(Double(sectionDuration) / settings.speed), 1000)
                compositionVideoTrack?.scaleTimeRange(timeRange, toDuration: scaledDuration)

                /// Speed up audio to max and remove remaining audio track to maintain the same length as the final video track
                if settings.speed >= MaxAudioSpeed {
                    let speedFactor = MaxAudioSpeed / settings.speed
                    let fractionedDuration = Int64(Double(sectionDuration) * speedFactor)
                    let cutOffStart = settings.start + Int64(Double(sectionDuration) * speedFactor)
                    let cutOffDuration = Int64(Double(sectionDuration) * (1.0 - speedFactor))
                    
                    /// Cut of audio track fraction that wont be sped up
                    timeRange = CMTimeRangeMake(CMTimeMake(cutOffStart, 1000), CMTimeMake(cutOffDuration, 1000))
                    compositionAudioTrack?.removeTimeRange(timeRange)
                    timeRange = CMTimeRangeMake(CMTimeMake(settings.start, 1000), CMTimeMake(fractionedDuration, 1000))
                }
                compositionAudioTrack?.scaleTimeRange(timeRange, toDuration: scaledDuration)
            })
            compositionVideoTrack?.preferredTransform = videoTrack.preferredTransform
            
            let exporter = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetMediumQuality)
            exporter?.outputURL = outputFileUrl
            exporter?.outputFileType = AVFileType.mp4
            exporter?.shouldOptimizeForNetworkUse = true
            exporter?.exportAsynchronously(completionHandler: {
                completion(exporter)
            })
        } catch let error {
            print(error.localizedDescription)
            completion(nil)
            return
        }
    }
}

func printFileSizeInMB(filePath: String) {
    let attr = try? FileManager.default.attributesOfItem(atPath: filePath)
    var fileSize = attr?[FileAttributeKey.size] as! UInt64
    //if you convert to NSDictionary, you can get file size old way as well.
    let dict = attr! as NSDictionary
    fileSize = dict.fileSize()
    let bcf = ByteCountFormatter()
    bcf.allowedUnits = [.useMB] // optional: restricts the units to MB only
    bcf.countStyle = .file
    let string = bcf.string(fromByteCount: Int64(fileSize))
    print("formatted result: \(string)")
}
