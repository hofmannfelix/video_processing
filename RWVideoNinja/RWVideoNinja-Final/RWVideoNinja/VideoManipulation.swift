
import UIKit
import AVFoundation

class VideoManipulation {
  
  //static let fps = asset.tracks(withMediaType: .video).first?.nominalFrameRate
  static let targetFps = 30
  static let videoSpeed = 2.0

  static func generateTimelapse(filePath: String, completion: @escaping (URL) -> ()) {
    let fileUrl = URL(fileURLWithPath: filePath)
    let asset = AVURLAsset(url: fileUrl, options: nil)
    generateTimelapse(asset: asset, completion: completion)
  }
  
  static func generateTimelapse(asset: AVAsset, completion: @escaping (URL) -> ()) {
    generateImages(asset: asset, completion: { frames in
      print("all frames extracted")
      generateVideoFromFrames(frames: frames, fps: targetFps, completion: { fileUrl in
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
    generator.generateCGImagesAsynchronously(forTimes: frameForTimes, completionHandler: { requestedTime, image, actualTime, result, error in
      DispatchQueue.main.async {
        if let image = image {
          print(requestedTime.value, requestedTime.seconds, actualTime.value)
          //TODO: write image directly to asset writer here and don`t save to avoid memory issue
          frames.append(image)
          if frames.count >= sampleCounts {
            completion(frames)
          }
        }
      }
    })
  }
  
  static func generateVideoFromFrames(frames: [CGImage], fps: Int, completion: @escaping (URL) -> ()) {
    let frameRate = CMTimeMake(1, Int32(Double(60*fps/60)))
    let width = frames.first?.width ?? 0, height = frames.first?.height ?? 0
    let settings = ImagesToVideoUtils.videoSettings(width: width, height: height)
    let utils = ImagesToVideoUtils(videoSettings: settings, frameRate: frameRate)
    utils.createMovieFromSource(frames: frames, withCompletion: { url in
      print(url)
      completion(url)
    })
  }
  
  static func mergeVideos(firstAsset: AVAsset, secondAsset: AVAsset, completion: @escaping (URL) -> ()) {
    let mixComposition = AVMutableComposition()
    
    // 2 - Create two video tracks
    guard let firstTrack = mixComposition.addMutableTrack(withMediaType: .video,
                                                          preferredTrackID: Int32(kCMPersistentTrackID_Invalid)) else { return }
    do {
      try firstTrack.insertTimeRange(CMTimeRangeMake(kCMTimeZero, firstAsset.duration),
                                     of: firstAsset.tracks(withMediaType: .video)[0],
                                     at: kCMTimeZero)
    } catch {
      print("Failed to load first track")
      return
    }
    
    guard let secondTrack = mixComposition.addMutableTrack(withMediaType: .video,
                                                           preferredTrackID: Int32(kCMPersistentTrackID_Invalid)) else { return }
    do {
      try secondTrack.insertTimeRange(CMTimeRangeMake(kCMTimeZero, secondAsset.duration),
                                      of: secondAsset.tracks(withMediaType: .video)[0],
                                      at: kCMTimeZero)
    } catch {
      print("Failed to load second track")
      return
    }
    
    // 2.1
    let mainInstruction = AVMutableVideoCompositionInstruction()
    mainInstruction.timeRange = CMTimeRangeMake(kCMTimeZero, CMTimeMaximum(firstAsset.duration, secondAsset.duration))
    
    // 2.2
    let firstInstruction = VideoHelper.videoCompositionInstruction(firstTrack, asset: firstAsset)
    firstInstruction.setOpacity(0.0, at: firstAsset.duration)
    let secondInstruction = VideoHelper.videoCompositionInstruction(secondTrack, asset: secondAsset)
    
    // 2.3
    mainInstruction.layerInstructions = [firstInstruction, secondInstruction]
    let mainComposition = AVMutableVideoComposition()
    mainComposition.instructions = [mainInstruction]
    mainComposition.frameDuration = CMTimeMake(1, 30)
    mainComposition.renderSize = CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
    
    // 3 - Audio track
    let audioTrack = mixComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: 0)
    do {
      try audioTrack?.insertTimeRange(CMTimeRangeMake(kCMTimeZero, firstAsset.duration),
                                      of: firstAsset.tracks(withMediaType: .audio)[0] ,
                                      at: kCMTimeZero)
    } catch {
      print("Failed to load Audio track")
    }
    
    // 4 - Get path
    guard let documentDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
    let dateFormatter = DateFormatter()
    dateFormatter.dateStyle = .long
    dateFormatter.timeStyle = .short
    let date = dateFormatter.string(from: Date())
    let url = documentDirectory.appendingPathComponent("mergeVideo-\(date).mov")
    
    // 5 - Create Exporter
    guard let exporter = AVAssetExportSession(asset: mixComposition, presetName: AVAssetExportPresetHighestQuality) else { return }
    exporter.outputURL = url
    exporter.outputFileType = AVFileType.mov
    exporter.shouldOptimizeForNetworkUse = true
    exporter.videoComposition = mainComposition
    
    // 6 - Perform the Export
    exporter.exportAsynchronously() {
      DispatchQueue.main.async {
        if let url = exporter.outputURL {
          completion(url)
        }
      }
    }
  }
}
