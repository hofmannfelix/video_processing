import AVFoundation
import UIKit

protocol FrameProvider {
  var totalFrames: Int { get }
  var frameIndex: Int { get }
  var frameSize: CGSize { get }
  var hasFrames: Bool { get }
  var nextFrame: CGImage? { get }
  var nextFrameBuffer: CVPixelBuffer? { get }
}

class BufferedFrameProvider: FrameProvider {
  let frameSize: CGSize
  let totalFrames: Int
  var frameIndex: Int = 0
  var frames = [CGImage]()
  var currentFrame: CGImage? = nil
  
  init(totalFrames: Int, frameSize: CGSize) {
    self.totalFrames = totalFrames
    self.frameSize = frameSize
  }
  
  var hasFrames: Bool {
    return frameIndex < totalFrames
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
  
  var nextFrameBuffer: CVPixelBuffer? {
    return BufferGenerator.newPixelBufferFrom(cgImage: nextFrame)
  }
  
  func pushFrame(frame: CGImage) {
    DispatchQueue.main.async {
      self.frames.append(frame)
      print("pushed new frame")
    }
  }
}

class FileFrameProvider: FrameProvider {
  let totalFrames: Int
  let filesPath: String
  var frameSize: CGSize = .zero
  var frameIndex: Int = 0
  var hasFrames: Bool = false
  
  init(filesPath: String, totalFrames: Int) {
    self.filesPath = filesPath
    self.totalFrames = totalFrames
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
  
  var nextFrameBuffer: CVPixelBuffer? {
    return BufferGenerator.newPixelBufferFrom(cgImage: nextFrame)
  }
  
  private var frameAtCurrentIndex: CGImage? {
    let path = filesPath.contains("%@") ? String(format: filesPath, String(frameIndex)) : filesPath
    return UIImage(contentsOfFile: path)?.cgImage
  }
}

class ArrayFrameProvider: FrameProvider {
  let totalFrames: Int
  let frames: [CGImage]
  var frameIndex: Int = 0
  let frameSize: CGSize
  
  init(frames: [CGImage]) {
    frameSize = CGSize(width: frames.first?.width ?? 0, height: frames.first?.height ?? 0)
    self.frames = frames
    self.totalFrames = frames.count
  }
  
  var hasFrames: Bool {
    return frameIndex < frames.count
  }
  
  var nextFrame: CGImage? {
    let frame = frames[frameIndex]
    frameIndex += 1
    return frame
  }
  
  var nextFrameBuffer: CVPixelBuffer? {
    return BufferGenerator.newPixelBufferFrom(cgImage: nextFrame)
  }
}

class MixedFrameProvider: FrameProvider {
  let frameProvider: [FrameProvider]
  let maxFrameProvider: FrameProvider
  var frameForIndex: [(Int, CGImage?)]
  let totalFrames: Int
  let frameSize: CGSize

  init(provider: [FrameProvider]) {
    frameProvider = provider
    frameForIndex = provider.map({ _ in return (-1, nil) })
    maxFrameProvider = provider.max(by: { $0.totalFrames < $1.totalFrames })!
    totalFrames = maxFrameProvider.totalFrames
    let width = provider.max(by: { $0.frameSize.width < $1.frameSize.width })?.frameSize.width ?? 0
    let height = provider.max(by: { $0.frameSize.height < $1.frameSize.height })?.frameSize.height ?? 0
    frameSize = CGSize(width: width, height: height)
  }
  
  var frameIndex: Int {
    return maxFrameProvider.frameIndex
  }
  
  var hasFrames: Bool {
    return maxFrameProvider.hasFrames
  }
  
  var nextFrame: CGImage? {
    fatalError("Not implemented for Mixed Frame Provider")
  }
  
  var nextFrameBuffer: CVPixelBuffer? {
    var frames = [CGImage]()
    let nextIndex = Double(frameIndex)
    for i in 0 ..< frameProvider.count {
      let provider = frameProvider[i]
      let index = Int(nextIndex * Double(provider.totalFrames)/Double(maxFrameProvider.totalFrames))
      guard let frame = frameForIndex[i].0 == index ? frameForIndex[i].1 : provider.nextFrame else {
        return nil
      }
      frameForIndex[i] = (index, frame)
      frames.append(frame)
    }
    return BufferGenerator.newPixelBufferFrom(cgImages: frames,
                                              width: Int(frameSize.width),
                                              height: Int(frameSize.height))
  }
}

private class BufferGenerator {
  
  static func newPixelBufferFrom(cgImage: CGImage?) -> CVPixelBuffer? {
    guard let img = cgImage else { return nil }
    return newPixelBufferFrom(cgImages: [img], width: img.width, height: img.height)
  }
  
  static func newPixelBufferFrom(cgImages: [CGImage?], width: Int, height: Int) -> CVPixelBuffer? {
    guard !cgImages.isEmpty else { return nil }
    let options:[String: Any] = [kCVPixelBufferCGImageCompatibilityKey as String: true, kCVPixelBufferCGBitmapContextCompatibilityKey as String: true]
    var pxbuffer:CVPixelBuffer?
    let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, options as CFDictionary?, &pxbuffer)
    assert(status == kCVReturnSuccess && pxbuffer != nil, "newPixelBuffer failed")
    
    CVPixelBufferLockBaseAddress(pxbuffer!, CVPixelBufferLockFlags(rawValue: 0))
    let pxdata = CVPixelBufferGetBaseAddress(pxbuffer!)
    let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
    let rect = CGRect(x: 0, y: 0, width: width, height: height)
    let context = CGContext(data: pxdata, width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pxbuffer!), space: rgbColorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
    assert(context != nil, "context is nil")
    
    context!.clear(rect)
    context!.concatenate(CGAffineTransform.identity)
    cgImages.forEach { cgImage in
      if let img = cgImage {
        context!.draw(img, in: rect)
      }
    }
    CVPixelBufferUnlockBaseAddress(pxbuffer!, CVPixelBufferLockFlags(rawValue: 0))
    return pxbuffer
  }
}
