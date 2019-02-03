import AVFoundation
import UIKit

protocol FrameProvider {
  var frameSize: CGSize { get }
  var hasFrames: Bool { get }
  var nextFrame: CGImage? { get }
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

class FileFrameProvider: FrameProvider {
  let frameSize: CGSize
  let filesPath: String
  var frameIndex: Int = 0
  var hasFrames: Bool
  
  init(frameSize: CGSize, filesPath: String) {
    self.frameSize = frameSize
    self.filesPath = filesPath
    self.hasFrames = true
  }
  
  var nextFrame: CGImage? {
    let path = filesPath.contains("%@") ? String(format: filesPath, frameIndex) : filesPath
    if let frame = UIImage(contentsOfFile: path)?.cgImage {
      frameIndex += 1
      return frame
    } else {
      hasFrames = false
      return nil
    }
  }
}
