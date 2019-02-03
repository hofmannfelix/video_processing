import Foundation
import AVFoundation
import UIKit

typealias ImageToVideoCompletion = (URL) -> Void

protocol FrameProvider {
  var frameSize: CGSize { get }
  var hasFrames: Bool { get }
  var nextFrame: CGImage? { get }
}

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
    if(FileManager.default.fileExists(atPath: ImageToVideoGenerator.tempPath)){
      guard (try? FileManager.default.removeItem(atPath: ImageToVideoGenerator.tempPath)) != nil else {
        print("remove path failed")
        return
      }
    }
    let videoSettings:[String: Any] = [AVVideoCodecKey: AVVideoCodecType.jpeg, //AVVideoCodecH264,
      AVVideoWidthKey: Int(frameProvider.frameSize.width),
      AVVideoHeightKey: Int(frameProvider.frameSize.width)]
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
          guard let frame = self.frameProvider.nextFrame else { continue }
          if let sampleBuffer = self.newPixelBufferFrom(cgImage: frame) {
            if i == 0 {
              self.bufferAdapter.append(sampleBuffer, withPresentationTime: kCMTimeZero)
            } else {
              let value = i - 1
              let lastTime = CMTimeMake(Int64(value), self.frameRate.timescale)
              let presentTime = CMTimeAdd(lastTime, self.frameRate)
              self.bufferAdapter.append(sampleBuffer, withPresentationTime: presentTime)
            }
            i += 1
          }
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
  
  func newPixelBufferFrom(cgImage:CGImage) -> CVPixelBuffer?{
    let options:[String: Any] = [kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true]
    var pxbuffer:CVPixelBuffer?
    let frameWidth = cgImage.width
    let frameHeight = cgImage.height
    let status = CVPixelBufferCreate(kCFAllocatorDefault, frameWidth, frameHeight, kCVPixelFormatType_32ARGB, options as CFDictionary?, &pxbuffer)
    assert(status == kCVReturnSuccess && pxbuffer != nil, "newPixelBuffer failed")
    
    CVPixelBufferLockBaseAddress(pxbuffer!, CVPixelBufferLockFlags(rawValue: 0))
    let pxdata = CVPixelBufferGetBaseAddress(pxbuffer!)
    let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
    let context = CGContext(data: pxdata, width: frameWidth, height: frameHeight, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pxbuffer!), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
    assert(context != nil, "context is nil")
    
    context!.concatenate(CGAffineTransform.identity)
    context!.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
    CVPixelBufferUnlockBaseAddress(pxbuffer!, CVPixelBufferLockFlags(rawValue: 0))
    return pxbuffer
  }
  
  //Helper methods
  /*static func orientationFromTransform(_ transform: CGAffineTransform) -> (orientation: UIImageOrientation, isPortrait: Bool) {
    var assetOrientation = UIImageOrientation.up
    var isPortrait = false
    if transform.a == 0 && transform.b == 1.0 && transform.c == -1.0 && transform.d == 0 {
      assetOrientation = .right
      isPortrait = true
    } else if transform.a == 0 && transform.b == -1.0 && transform.c == 1.0 && transform.d == 0 {
      assetOrientation = .left
      isPortrait = true
    } else if transform.a == 1.0 && transform.b == 0 && transform.c == 0 && transform.d == 1.0 {
      assetOrientation = .up
    } else if transform.a == -1.0 && transform.b == 0 && transform.c == 0 && transform.d == -1.0 {
      assetOrientation = .down
    }
    return (assetOrientation, isPortrait)
  }
  
  static func videoCompositionInstruction(_ track: AVCompositionTrack, asset: AVAsset) -> AVMutableVideoCompositionLayerInstruction {
    let instruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
    let assetTrack = asset.tracks(withMediaType: AVMediaType.video)[0]
    let transform = assetTrack.preferredTransform
    let assetInfo = orientationFromTransform(transform)
    
    var scaleToFitRatio = UIScreen.main.bounds.width / assetTrack.naturalSize.width
    if assetInfo.isPortrait {
      scaleToFitRatio = UIScreen.main.bounds.width / assetTrack.naturalSize.height
      let scaleFactor = CGAffineTransform(scaleX: scaleToFitRatio, y: scaleToFitRatio)
      instruction.setTransform(assetTrack.preferredTransform.concatenating(scaleFactor), at: kCMTimeZero)
    } else {
      let scaleFactor = CGAffineTransform(scaleX: scaleToFitRatio, y: scaleToFitRatio)
      var concat = assetTrack.preferredTransform.concatenating(scaleFactor)
        .concatenating(CGAffineTransform(translationX: 0, y: UIScreen.main.bounds.width / 2))
      if assetInfo.orientation == .down {
        let fixUpsideDown = CGAffineTransform(rotationAngle: CGFloat(Double.pi))
        let windowBounds = UIScreen.main.bounds
        let yFix = assetTrack.naturalSize.height + windowBounds.height
        let centerFix = CGAffineTransform(translationX: assetTrack.naturalSize.width, y: yFix)
        concat = fixUpsideDown.concatenating(centerFix).concatenating(scaleFactor)
      }
      instruction.setTransform(concat, at: kCMTimeZero)
    }
    return instruction
  }*/
}
