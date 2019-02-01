
import UIKit
import AVFoundation

class VideoManipulation {
  
  //static let fps = asset.tracks(withMediaType: .video).first?.nominalFrameRate
  static let targetFps = 60
  static let videoSpeed = 2.0

  static func generateTimelapse(filePath: String, completion: @escaping (URL) -> ()) {
    let fileUrl = URL(fileURLWithPath: filePath)
    let asset = AVURLAsset(url: fileUrl, options: nil)
    generateTimelapse(asset: asset, completion: completion)
  }
  
  static func generateTimelapse(asset: AVAsset, completion: @escaping (URL) -> ()) {

    generateImages(asset: asset, completion: { frames in
      print("all frames extracted")
      generateVideoFromFrames(frames: frames, completion: { fileUrl in
        print("video generation completed")
        completion(fileUrl)
      })
    })
  }
  
  static func generateImages(asset: AVAsset, completion: @escaping ([CGImage]) -> ()) {
    let videoDuration = asset.duration
    let generator = AVAssetImageGenerator(asset: asset)
    generator.requestedTimeToleranceAfter = kCMTimeZero
    generator.requestedTimeToleranceBefore = kCMTimeZero
    
    var frameForTimes = [NSValue]()
    let totalTimeLength = Int(videoDuration.seconds * Double(videoDuration.timescale))
    let sampleCounts = Int(videoDuration.seconds * (Double(targetFps) / videoSpeed))
    let step = totalTimeLength / sampleCounts
    
    for i in 0 ..< sampleCounts {
      let cmTime = CMTimeMake(Int64(i * step), Int32(videoDuration.timescale))
      frameForTimes.append(NSValue(time: cmTime))
    }
    
    var frames = [CGImage]()
    generator.generateCGImagesAsynchronously(forTimes: frameForTimes, completionHandler: {requestedTime, image, actualTime, result, error in
      DispatchQueue.main.async {
        if let image = image {
          print(requestedTime.value, requestedTime.seconds, actualTime.value)
          //TODO: write image directly to asset writer
          frames.append(image)
          if frames.count >= sampleCounts {
            completion(frames)
          }
        }
      }
    })
  }
  
  static func generateVideoFromFrames(frames: [CGImage], completion: @escaping (URL) -> ()) {
    let frameRate = CMTimeMake(1, Int32(Double(60*targetFps/60)))
    let width = frames.first?.width ?? 0, height = frames.first?.height ?? 0
    let settings = ImagesToVideoUtils.videoSettings(width: width, height: height)
    let utils = ImagesToVideoUtils(videoSettings: settings, frameRate: frameRate)
    utils.createMovieFromSource(frames: frames, withCompletion: { url in
      print(url)
      completion(url)
    })
  }
}
