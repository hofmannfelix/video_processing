import Flutter
import UIKit
import AVFoundation
import MobileCoreServices

public class VideoProcessSettings {
    final let start: Int64
    final var end: Int64
    final var speed: Double?
    final var text: String?
    
    init(start: Int64, end: Int64, speed: Double?, text: String?) {
        self.start = start
        self.end = end
        self.speed = speed
        self.text = text
    }
}

public class SwiftVideoProcessingPlugin: NSObject, FlutterPlugin {
    public static var _channel: FlutterMethodChannel?
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        _channel = FlutterMethodChannel(name: "video_processing", binaryMessenger: registrar.messenger())
        let instance = SwiftVideoProcessingPlugin()
        registrar.addMethodCallDelegate(instance, channel: _channel!)
    }
    
    private let MaxAudioSpeed = 10.0
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if call.method == "processVideo" {
            if let args = call.arguments as? [AnyObject],
                let inputPath = args[0] as? String,
                let outputPath = args[1] as? String,
                let settingsMap = args[2] as? [[String: AnyObject]] {
                let settings = settingsMap.map({VideoProcessSettings(start: Int64($0["start"] as! Int), end: Int64($0["end"] as! Int), speed: $0["speed"] as? Double, text: $0["text"] as? String)})
                
                let inputFileURL = URL(fileURLWithPath: inputPath)
                let outputFileURL = URL(fileURLWithPath: outputPath)
                scaleAsset(inputUrl: inputFileURL, outputFileUrl: outputFileURL, settings: settings) { (exporter) in
                    if let exporter = exporter {
                        switch exporter.status {
                        case .failed:
                            print(exporter.error?.localizedDescription ?? "Error in exporting..")
                            //send error to progress method
                            break
                        case .completed:
                            print("Scaled video has been generated successfully!")
                            self.sendProgressForCurrentVideoProcess(taskId: outputFileURL.relativePath, progress: 1.0)
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
    
    private func sendProgressForCurrentVideoProcess(taskId: String, progress: Double) {
        SwiftVideoProcessingPlugin._channel?.invokeMethod("updateProgress", arguments: ["taskId": taskId, "progress": progress])
    }
    
    private func scaleAsset(inputUrl: URL, outputFileUrl: URL, settings: [VideoProcessSettings], completion: @escaping (_ exporter: AVAssetExportSession?) -> Void) {
        let asset = AVAsset(url: inputUrl)
        let timeRange = CMTimeRangeMake(kCMTimeZero, asset.duration)
        let videoTracks = asset.tracks(withMediaType: AVMediaType.video)
        if videoTracks.isEmpty {
            completion(nil)
            return
        }
        do {
            //Currently only supports either speed settings or text settings
            let isSpeedAnimation = settings.first?.speed != nil
            let isTextAnimation = settings.first?.text != nil
            
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
            if isSpeedAnimation {
                settings.forEach({ settings in
                    if settings.speed ?? 1.0 == 1.0 { return }
                    
                    let sectionDuration = settings.end - settings.start
                    var timeRange = CMTimeRangeMake(CMTimeMake(settings.start, 1000), CMTimeMake(sectionDuration, 1000))
                    let scaledDuration = CMTimeMake(Int64(Double(sectionDuration) / settings.speed!), 1000)
                    compositionVideoTrack?.scaleTimeRange(timeRange, toDuration: scaledDuration)

                    /// Speed up audio to max and remove remaining audio track to maintain the same length as the final video track
                    if settings.speed! >= MaxAudioSpeed {
                        let speedFactor = MaxAudioSpeed / settings.speed!
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
            }
            compositionVideoTrack?.preferredTransform = videoTrack.preferredTransform
            
            let exporter = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetMediumQuality)
            let timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] (_) in
                self?.sendProgressForCurrentVideoProcess(taskId: outputFileUrl.relativePath, progress: Double(exporter?.progress ?? 0.0))
                print("Progress is at", (exporter?.progress) ?? -1.0)
            }
            if isTextAnimation {
                exporter?.videoComposition = textLayerComposition(settings: settings, videoSize: CGSize(width: videoTrack.naturalSize.height, height: videoTrack.naturalSize.width), mixComposition: mixComposition)
            }
            exporter?.outputURL = outputFileUrl
            exporter?.outputFileType = AVFileType.mp4
            exporter?.shouldOptimizeForNetworkUse = true
            exporter?.exportAsynchronously(completionHandler: {
                timer.invalidate()
                completion(exporter)
            })
        } catch let error {
            print(error.localizedDescription)
            completion(nil)
            return
        }
    }
}

func textLayerComposition(settings: [VideoProcessSettings], videoSize: CGSize, mixComposition: AVMutableComposition) -> AVMutableVideoComposition {

    let parentLayer = CALayer()
    let videoLayer = CALayer()
    parentLayer.frame = CGRect(origin: CGPoint.zero, size: videoSize)
    videoLayer.frame = CGRect(origin: CGPoint.zero, size: videoSize)
    parentLayer.addSublayer(videoLayer)
    
    ///Text setup
    settings.forEach { settings in
        let start = Double(settings.start) / 1000.0
        let duration = Double(settings.end - settings.start) / 1000.0
        let videoText = CATextLayer()
        videoText.string = settings.text
        videoText.font = CTFontCreateSystemFontWithSize(size: 22)
        videoText.frame = CGRect(origin: CGPoint.zero, size: videoSize)
        videoText.alignmentMode = kCAAlignmentCenter
        videoText.foregroundColor = UIColor(red: 0.7, green: 0.0, blue: 1.0, alpha: 1.0).cgColor
        videoText.add(subtitleAnimation(at: start, for: duration), forKey: "opacityLayer\(0)")
        parentLayer.addSublayer(videoText)
    }
    
    let videoTrack = mixComposition.tracks(withMediaType: AVMediaType.video).first
    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: videoTrack!)
    layerInstruction.setTransform(videoTrack!.preferredTransform, at: kCMTimeZero)
    
    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: kCMTimeZero, duration: mixComposition.duration)
    instruction.layerInstructions = [layerInstruction]
    
    let videoComposition = AVMutableVideoComposition()
    videoComposition.frameDuration = CMTimeMake(1, 30)
    videoComposition.renderSize = videoSize
    videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(postProcessingAsVideoLayer: videoLayer, in: parentLayer)
    videoComposition.instructions = [instruction]
    return videoComposition
}

func getSubtitlesAnimation(duration: CFTimeInterval,startTime:Double)->CAKeyframeAnimation {
    let animation = CAKeyframeAnimation(keyPath:"opacity")
    animation.duration = duration
    animation.calculationMode = kCAAnimationDiscrete
    animation.values = [0,1,1,0,0]
    animation.keyTimes = [0,0.001,0.99,0.999,1]
    animation.isRemovedOnCompletion = false
    animation.fillMode = kCAFillModeBoth
    animation.beginTime = AVCoreAnimationBeginTimeAtZero + startTime
    return animation
}

func CTFontCreateSystemFontWithSize(size: CGFloat) -> CTFont {
    return CTFontCreateWithName("TimesNewRomanPSMT" as CFString, size,  nil)
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
