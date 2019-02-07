import UIKit
import AVFoundation
import MobileCoreServices

class VideoManipulation {
  
  static func generateVideo(assetPaths: [String], outputFps: Int, outputSpeed: Double, completion: @escaping (URL?) -> ()) {
    let isImg: (String) -> Bool = { $0.contains(".jpg") || $0.contains(".png") }
    let providers = assetPaths
      .map { path -> FrameProvider? in
        return isImg(path.lowercased())
          ? FileFrameProvider(filesPath: path)
          : generateImages(filePath: path, fps: outputFps, speed: outputSpeed)
      }
      .filter { $0 != nil }
      .map { $0! }
    let mixedProvider = MixedFrameProvider(provider: providers)
    generateVideoFromFrames(with: mixedProvider, fps: outputFps, speed: outputSpeed, completion: completion)
  }
  
  static func generateVideoFromFrames(with frameProvider: FrameProvider, fps: Int, speed: Double, completion: @escaping (URL?) -> ()) {
    let frameRate = CMTimeMake(1, Int32(Double(60*fps/60)))
    let generator = ImageToVideoGenerator(frameProvider: frameProvider, frameRate: frameRate, completionBlock: completion)
    generator.startGeneration()
  }
  
  static func generateImages(filePath: String, fps: Int, speed: Double) -> BufferedFrameProvider? {
    let fileUrl = URL(fileURLWithPath: filePath)
    let asset = AVURLAsset(url: fileUrl, options: nil)
    let videoDuration = asset.duration
    let generator = AVAssetImageGenerator(asset: asset)
    generator.requestedTimeToleranceAfter = kCMTimeZero
    generator.requestedTimeToleranceBefore = kCMTimeZero
    
    guard let frameSize = asset.tracks(withMediaType: .video).first?.naturalSize else { return nil }
    var frameForTimes = [NSValue]()
    let totalTimeLength = Int(videoDuration.seconds * Double(videoDuration.timescale))
    let sampleCounts = Int(videoDuration.seconds * (Double(fps) / speed))
    let step = totalTimeLength / sampleCounts
    for i in 0 ..< sampleCounts {
      let cmTime = CMTimeMake(Int64(i * step), Int32(videoDuration.timescale))
      frameForTimes.append(NSValue(time: cmTime))
    }
    
    let frameProvider = BufferedFrameProvider(totalFrames: sampleCounts, frameSize: frameSize)
    generator.generateCGImagesAsynchronously(forTimes: frameForTimes, completionHandler: { requestedTime, image, actualTime, result, error in
        if let frame = image {
          frameProvider.pushFrame(frame: frame)
          
          let index = (requestedTime.value as Int64)/Int64(step)
          print(index, requestedTime.seconds, requestedTime.value, actualTime.value)
        }
    })
    return frameProvider
  }
}
