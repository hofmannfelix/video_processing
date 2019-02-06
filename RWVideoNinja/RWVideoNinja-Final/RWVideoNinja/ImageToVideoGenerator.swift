import Foundation
import AVFoundation
import UIKit

typealias ImageToVideoCompletion = (URL) -> Void

class ImageToVideoGenerator {
  
  static let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
  static let tempPath = paths[0] + "/exportvideo.mp4"
  static let fileURL = URL(fileURLWithPath: tempPath)
  
  private var assetWriter:AVAssetWriter!
  private var writeInput:AVAssetWriterInput!
  private var bufferAdapter:AVAssetWriterInputPixelBufferAdaptor!
  private var frameRate: CMTime!
  private var frameProvider: FrameProvider!
  private var completionBlock: ImageToVideoCompletion?
  
  public init(frameProvider: FrameProvider, frameRate: CMTime, completionBlock: ImageToVideoCompletion?) {
    if(FileManager.default.fileExists(atPath: ImageToVideoGenerator.tempPath)) {
      guard (try? FileManager.default.removeItem(atPath: ImageToVideoGenerator.tempPath)) != nil else {
        print("remove path failed")
        return
      }
    }
    let videoSettings:[String: Any] = [AVVideoCodecKey: AVVideoCodecType.jpeg, //AVVideoCodecH264,
      AVVideoWidthKey: Int(frameProvider.frameSize.width),
      AVVideoHeightKey: Int(frameProvider.frameSize.height)]
    self.assetWriter = try! AVAssetWriter(url: ImageToVideoGenerator.fileURL, fileType: .mov)
    self.writeInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    assert(assetWriter.canAdd(self.writeInput), "add failed")
    self.assetWriter.add(self.writeInput)
    let bufferAttributes:[String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB)]
    self.bufferAdapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: self.writeInput, sourcePixelBufferAttributes: bufferAttributes)
    self.frameRate = frameRate
    self.frameProvider = frameProvider
    self.completionBlock = completionBlock
  }
  
  func startGeneration() {
    self.assetWriter.startWriting()
    self.assetWriter.startSession(atSourceTime: kCMTimeZero)
    var i = 0
    let mediaInputQueue = DispatchQueue(label: "mediaInputQueue")
    writeInput.requestMediaDataWhenReady(on: mediaInputQueue) {
      while self.frameProvider.hasFrames {
        if self.writeInput.isReadyForMoreMediaData {
          guard let buffer = self.frameProvider.nextFrameBuffer else { continue }
          print("Write Frame \(i)")
          if i == 0 {
            self.bufferAdapter.append(buffer, withPresentationTime: kCMTimeZero)
          } else {
            let value = i - 1
            let lastTime = CMTimeMake(Int64(value), self.frameRate.timescale)
            let presentTime = CMTimeAdd(lastTime, self.frameRate)
            self.bufferAdapter.append(buffer, withPresentationTime: presentTime)
          }
          i += 1
        }
      }
      self.writeInput.markAsFinished()
      self.assetWriter.finishWriting {
        DispatchQueue.main.sync {
          self.completionBlock?(ImageToVideoGenerator.fileURL)
        }
      }
    }
  }
}
