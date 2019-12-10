import Flutter
import UIKit
import AVFoundation
import MobileCoreServices

public class VideoSectionSettings {
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
        if call.method == "generateTimelapse" {
            if let args = call.arguments as? [AnyObject],
                let inputPath = args[0] as? String,
                let outputPath = args[1] as? String,
                let sectionSettings = args[2] as? [[AnyObject]] {
                let sectionSpeedSettings = sectionSettings.map({VideoSectionSettings(start: Int64($0[0] as! Int), end: Int64($0[1] as! Int), speed: $0[2] as? Double ?? 1.0)})
                
                
            }
        }
        if call.method == "generateVideo" {
            if let args = call.arguments as? [AnyObject],
                let paths = args[0] as? [String],
                let filename = args[1] as? String,
                let fps = args[2] as? Int,
                let speed = args[3] as? Double {
                
                // Initialize Exporter now
                let docDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
                let path = docDir + "/" + filename + ".mp4"
                let inputFileURL = URL(fileURLWithPath: paths.first!)
                let outputFileURL = URL(fileURLWithPath: path)
                if FileManager.default.isDeletableFile(atPath: outputFileURL.relativePath) {
                    try? FileManager.default.removeItem(at: outputFileURL)
                }
                
                VSVideoSpeeder.shared.scaleAsset(fromURL: inputFileURL, with: outputFileURL, by: Int64(speed)) { (exporter) in
                    if let exporter = exporter {
                        switch exporter.status {
                        case .failed:
                            print(exporter.error?.localizedDescription ?? "Error in exporting..")
                            break
                        case .completed:
                            print("Scaled video has been generated successfully!")
                            printFileSizeInMB(filePath: outputFileURL.relativePath)
                            result(outputFileURL.relativePath)
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
    
    /// Singleton instance of `VSVideoSpeeder`
    static var shared: VSVideoSpeeder = {
        return VSVideoSpeeder()
    }()
    
    func scaleAsset(fromURL url: URL, with outputFileUrl: URL, by scale: Int64, completion: @escaping (_ exporter: AVAssetExportSession?) -> Void) {
        
        /// Asset
        let asset = AVAsset(url: url)
        
        /// Video Tracks
        let videoTracks = asset.tracks(withMediaType: AVMediaType.video)
        if videoTracks.count == 0 {
            /// Can not find any video track
            completion(nil)
            return
        }
        
        /// Get the scaled video duration
        //TODO: make multiple scaledVideoDurations
        let scaledVideoDuration = CMTimeMake(asset.duration.value / scale, asset.duration.timescale)
        let timeRange = CMTimeRangeMake(kCMTimeZero, asset.duration)
        
        /// Video track
        let videoTrack = videoTracks.first!
        let mixComposition = AVMutableComposition()
        let compositionVideoTrack = mixComposition.addMutableTrack(withMediaType: AVMediaType.video, preferredTrackID: kCMPersistentTrackID_Invalid)
        
        /// Audio Tracks
        let audioTracks = asset.tracks(withMediaType: AVMediaType.audio)
        if audioTracks.count > 0 {
            /// Use audio if video contains the audio track
            let compositionAudioTrack = mixComposition.addMutableTrack(withMediaType: AVMediaType.audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            
            /// Audio track
            let audioTrack = audioTracks.first!
            do {
                try compositionAudioTrack?.insertTimeRange(timeRange, of: audioTrack, at: kCMTimeZero)
                compositionAudioTrack?.scaleTimeRange(timeRange, toDuration: scaledVideoDuration)
            } catch _ {
                /// Ignore audio error
            }
        }
        
        do {
            try compositionVideoTrack?.insertTimeRange(timeRange, of: videoTrack, at: kCMTimeZero)
            compositionVideoTrack?.scaleTimeRange(timeRange, toDuration: scaledVideoDuration)
            
            /// Keep original transformation
            compositionVideoTrack?.preferredTransform = videoTrack.preferredTransform
            
            let exporter = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetHighestQuality)
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
