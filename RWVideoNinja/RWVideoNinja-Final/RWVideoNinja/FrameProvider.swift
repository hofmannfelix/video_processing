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
  let filesPath: String
  var frameSize: CGSize = .zero
  var frameIndex: Int = 1
  var hasFrames: Bool = false
  
  init(filesPath: String) {
    self.filesPath = filesPath
    if let frame = frameAtCurrentIndex {
      frameSize = CGSize(width: frame.width, height: frame.height)
      hasFrames = true
    }
  }
  
  var nextFrame: CGImage? {
    if let frame = frameAtCurrentIndex {
      frameIndex += 1
      return frame
    } else {
      hasFrames = false
      return nil
    }
  }
  
  private var frameAtCurrentIndex: CGImage? {
    let path = filesPath.contains("%@") ? String(format: filesPath, String(frameIndex)) : filesPath
    return UIImage(contentsOfFile: path)?.cgImage
  }
}

class ArrayFrameProvider: FrameProvider {
  let frames: [CGImage]
  var index: Int = 0
  let frameSize: CGSize
  
  var hasFrames: Bool {
    return index < frames.count
  }
  
  var nextFrame: CGImage? {
    let frame = frames[index]
    index += 1
    return frame
  }
  
  init(frames: [CGImage]) {
    frameSize = CGSize(width: frames.first?.width ?? 0, height: frames.first?.height ?? 0)
    self.frames = frames
  }
}
