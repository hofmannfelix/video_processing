
import UIKit
import AVFoundation
import MobileCoreServices

class VideoManipulation {
  
  //static let fps = asset.tracks(withMediaType: .video).first?.nominalFrameRate

  static func generateTimelapse(filePath: String, fps: Int, speed: Double, completion: @escaping (URL?) -> ()) {
    let fileUrl = URL(fileURLWithPath: filePath)
    let asset = AVURLAsset(url: fileUrl, options: nil)
    generateTimelapse(asset: asset, fps: fps, speed: speed, completion: completion)
  }
  
  static func generateTimelapse(asset: AVAsset, fps: Int, speed: Double, completion: @escaping (URL?) -> ()) {
    guard let frameProvider = generateImages(asset: asset, fps: fps, speed: speed) else {
      completion(nil)
      return
    }
    generateVideoFromFrames(with: frameProvider, fps: fps, speed: speed, completion: completion)
  }
  
  static func generateImages(asset: AVAsset, fps: Int, speed: Double) -> BufferedFrameProvider? {
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
  
  static func generateVideoFromFrames(with frameProvider: FrameProvider, fps: Int, speed: Double, completion: @escaping (URL) -> ()) {
    let frameRate = CMTimeMake(1, Int32(Double(60*fps/60)))
    let generator = ImageToVideoGenerator(frameProvider: frameProvider, frameRate: frameRate, completionBlock: completion)
    generator.startGeneration()
  }
  
//  private static func createDirectory(_ directory: String) -> URL? {
//    //let fileExists = FileManager.default.fileExists(atPath: fileLocation)
//
//    let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
//    let dataPath = documentsDirectory.appendingPathComponent(directory)
//    do {
//      try FileManager.default.createDirectory(atPath: dataPath.absoluteString, withIntermediateDirectories: false, attributes: nil)
//    } catch let error {
//      print(error.localizedDescription);
//    }
//    return dataPath
//  }
//
//  private static func writeCGImage(_ image: CGImage, to destinationURL: URL, filename: String) {
//    do {
//      if let mutableData = CFDataCreateMutable(nil, 0),
//        let destination = CGImageDestinationCreateWithData(mutableData, kUTTypePNG, 1, nil) {
//        CGImageDestinationAddImage(destination, image, nil)
//        if CGImageDestinationFinalize(destination) {
//          let data = mutableData as Data
//          try data.write(to: destinationURL.appendingPathComponent(filename))
//        }
//      }
//    } catch let error {
//      print(error.localizedDescription)
//    }
//  }
  
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

class BufferedFrameProvider: FrameProvider {
  let frameSize: CGSize
  let numberOfFrames: Int
  var frameIndex: Int = 0
  var frames = [CGImage]()
  var currentFrame: CGImage? = nil
  
  init(totalFrames: Int, frameSize: CGSize) {
    self.numberOfFrames = totalFrames
    self.frameSize = frameSize
  }
  
  var hasFrames: Bool {
    return frameIndex < numberOfFrames
  }
  
  var nextFrame: CGImage? {
    currentFrame = nil
    if !frames.isEmpty {
      DispatchQueue.main.async {
        self.currentFrame = self.frames.removeFirst()
        self.frameIndex += 1
        print("read frame with index \(self.frameIndex)")
      }
      while currentFrame == nil {}
    }
    return currentFrame
  }
  
  func pushFrame(frame: CGImage) {
    DispatchQueue.main.async {
      self.frames.append(frame)
      print("pushed new frame")
    }
  }
}

//class FileFrameProvider: FrameProvider {
//  var frameSize: CGSize
//  
//  var hasFrames: Bool
//  
//  var nextFrame: CGImage?
//  
//}
