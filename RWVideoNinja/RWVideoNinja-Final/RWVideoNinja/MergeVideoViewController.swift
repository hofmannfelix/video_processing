/// Copyright (c) 2018 Razeware LLC
///
/// Permission is hereby granted, free of charge, to any person obtaining a copy
/// of this software and associated documentation files (the "Software"), to deal
/// in the Software without restriction, including without limitation the rights
/// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
/// copies of the Software, and to permit persons to whom the Software is
/// furnished to do so, subject to the following conditions:
///
/// The above copyright notice and this permission notice shall be included in
/// all copies or substantial portions of the Software.
///
/// Notwithstanding the foregoing, you may not use, copy, modify, merge, publish,
/// distribute, sublicense, create a derivative work, and/or sell copies of the
/// Software in any work that is designed, intended, or marketed for pedagogical or
/// instructional purposes related to programming, coding, application development,
/// or information technology.  Permission for such use, copying, modification,
/// merger, publication, distribution, sublicensing, creation of derivative works,
/// or sale is expressly withheld.
///
/// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
/// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
/// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
/// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
/// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
/// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
/// THE SOFTWARE.

import UIKit
import MobileCoreServices
import MediaPlayer
import Photos
import AVKit

class MergeVideoViewController: UIViewController {
  var assetUrl: URL?
  var firstAsset: AVAsset?
  var secondAsset: AVAsset?
  var audioAsset: AVAsset?
  var loadingAssetOne = false
  
  @IBOutlet var activityMonitor: UIActivityIndicatorView!
  
  func savedPhotosAvailable() -> Bool {
    guard !UIImagePickerController.isSourceTypeAvailable(.savedPhotosAlbum) else { return true }
    
    let alert = UIAlertController(title: "Not Available", message: "No Saved Album found", preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.cancel, handler: nil))
    present(alert, animated: true, completion: nil)
    return false
  }
    
  func exportDidFinish(_ session: AVAssetExportSession) {
    
    // Cleanup assets
    activityMonitor.stopAnimating()
    firstAsset = nil
    secondAsset = nil
    audioAsset = nil
    
    guard session.status == AVAssetExportSessionStatus.completed,
    let outputURL = session.outputURL else { return }
    
    let saveVideoToPhotos = {
      PHPhotoLibrary.shared().performChanges({ PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputURL) }) { saved, error in
        let success = saved && (error == nil)
        let title = success ? "Success" : "Error"
        let message = success ? "Video saved" : "Failed to save video"
        
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.cancel, handler: nil))
        self.present(alert, animated: true, completion: nil)
      }
    }
    
    // Ensure permission to access Photo Library
    if PHPhotoLibrary.authorizationStatus() != .authorized {
      PHPhotoLibrary.requestAuthorization({ status in
        if status == .authorized {
          saveVideoToPhotos()
        }
      })
    } else {
      saveVideoToPhotos()
    }
  }
  
  @IBAction func loadAssetOne(_ sender: AnyObject) {
    if savedPhotosAvailable() {
      loadingAssetOne = true
      VideoHelper.startMediaBrowser(delegate: self, sourceType: .savedPhotosAlbum)
    }
  }
  
  @IBAction func loadAssetTwo(_ sender: AnyObject) {
    if savedPhotosAvailable() {
      loadingAssetOne = false
      VideoHelper.startMediaBrowser(delegate: self, sourceType: .savedPhotosAlbum)
    }
  }
  
  @IBAction func loadAudio(_ sender: AnyObject) {
    let mediaPickerController = MPMediaPickerController(mediaTypes: .any)
    mediaPickerController.delegate = self
    mediaPickerController.prompt = "Select Audio"
    present(mediaPickerController, animated: true, completion: nil)
  }
    
  @IBAction func merge(_ sender: AnyObject) {
    guard let firstAsset = firstAsset, let secondAsset = secondAsset else { return }
    
    activityMonitor.startAnimating()
    
    // 1 - Create AVMutableComposition object. This object will hold your AVMutableCompositionTrack instances.
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
                                      at: kCMTimeZero) // firstAsset.duration
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
    if let loadedAudioAsset = audioAsset {
      let audioTrack = mixComposition.addMutableTrack(withMediaType: .audio, preferredTrackID: 0)
      do {
        try audioTrack?.insertTimeRange(CMTimeRangeMake(kCMTimeZero, CMTimeAdd(firstAsset.duration, secondAsset.duration)),
                                        of: loadedAudioAsset.tracks(withMediaType: .audio)[0] ,
                                        at: kCMTimeZero)
      } catch {
        print("Failed to load Audio track")
      }
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
        self.exportDidFinish(exporter)
      }
    }
  }
  
  @IBAction func generateTimelapse(_ sender: AnyObject) {
    guard let asset = firstAsset else { return }
//    VideoManipulation.generateTimelapse(asset: asset, fps: 30, speed: 2, completion: { fileUrl in
//      guard let url = fileUrl else { return }
//
//      let player = AVPlayer(url: url)
//      let playerController = AVPlayerViewController()
//      playerController.player = player
//      self.present(playerController, animated: true) {
//        player.play()
//      }
//    })
  }
  
  @IBAction func generateDuration(_ sender: AnyObject) {
    guard let assetPath = assetUrl?.relativePath else { return }
    
    let dirPaths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    let docsFolder = dirPaths!.appendingPathComponent("test").relativePath
    let filepath = docsFolder + "/countdown-%@.png"
    
    print("File 1: ", assetPath)
    print("File 2: ", filepath)
    
    VideoManipulation.generateVideo(assetPaths: [assetPath, filepath], outputFps: 30, outputSpeed: 2) { url in
      guard let url = url else { return }
      print("generation completed")

      let player = AVPlayer(url: url)
      let playerController = AVPlayerViewController()
      playerController.player = player
      self.present(playerController, animated: true) {
        player.play()
      }
    }
    
    //guard let asset = firstAsset else { return }
    
//    let fileProvider = FileFrameProvider(filesPath: filepath)
//    let bufferedProvider = VideoManipulation.generateImages(asset: firstAsset!, fps: 30, speed: 2)
//    let mixedProvider = MixedFrameProvider(provider: [bufferedProvider!, fileProvider])
//
//    VideoManipulation.generateVideoFromFrames(with: mixedProvider, fps: 30, speed: 2) { url in
//      guard let url = url else { return }
//      print("generation completed")
//
//      self.firstAsset = AVAsset(url: url)
//
//      let player = AVPlayer(url: url)
//      let playerController = AVPlayerViewController()
//      playerController.player = player
//      self.present(playerController, animated: true) {
//        player.play()
//      }
//    }
    
//    let label = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
//    label.text = "Test label"
//    label.textColor = .white
//    label.backgroundColor = .red
//    let cgImg = image(with: label)!.cgImage!
//    let img = UIImage.init(cgImage: cgImg)
//    let data = UIImageJPEGRepresentation(img, 1)
//    var frames = [CGImage]()
//    for i in 0..<10 {
//      frames.append(cgImg)
//      //try? data?.write(to: URL(fileURLWithPath: String.init(format: filepath, String(i))))
//    }
    
//    let frameProvider = ArrayFrameProvider(frames: frames)
//    VideoManipulation.generateVideoFromFrames(with: frameProvider, fps: 1, speed: 1) { fileUrl in
    
    
//
//    VideoManipulation.generateVideoFromFrames(with: mixedProvider, fps: 1, speed: 1) { fileUrl in
//        guard let url = fileUrl else { return }
//
//        self.firstAsset = AVAsset(url: url)
//
//        let player = AVPlayer(url: url)
//        let playerController = AVPlayerViewController()
//        playerController.player = player
//        self.present(playerController, animated: true) {
//            player.play()
//        }
//    }
    
//    VideoManipulation.generateVideoFromFrames(with: [img,img,img,img], fps: 1, speed: 1, completion: { fileUrl in
//
//      let player = AVPlayer(url: fileUrl)
//      let playerController = AVPlayerViewController()
//      playerController.player = player
//      self.present(playerController, animated: true) {
//        player.play()
//      }
//    })
  }
  
    private func copyFolders() {
      let filemgr = FileManager.default
      let dirPaths = filemgr.urls(for: .documentDirectory, in: .userDomainMask).first
      let folderPath = Bundle.main.resourceURL!.appendingPathComponent("testfiles").path
      let docsFolder = dirPaths!.appendingPathComponent("test").path
      if !filemgr.fileExists(atPath: docsFolder) {
        copyFiles(pathFromBundle: folderPath, pathDestDocs: docsFolder)
      } else {
        print("Files exist")
      }
    }

    private func copyFiles(pathFromBundle : String, pathDestDocs: String) {
      let fileManagerIs = FileManager.default
      do {
        let filelist = try fileManagerIs.contentsOfDirectory(atPath: pathFromBundle)
        try? fileManagerIs.copyItem(atPath: pathFromBundle, toPath: pathDestDocs)
        
        for filename in filelist {
          try? fileManagerIs.copyItem(atPath: "\(pathFromBundle)/\(filename)", toPath: "\(pathDestDocs)/\(filename)")
        }
      } catch {
        print("\nError\n")
      }
    }
  
  private func image(with view: UIView) -> UIImage? {
    UIGraphicsBeginImageContextWithOptions(view.bounds.size, view.isOpaque, 0.0)
    defer { UIGraphicsEndImageContext() }
    if let context = UIGraphicsGetCurrentContext() {
      view.layer.render(in: context)
      let image = UIGraphicsGetImageFromCurrentImageContext()
      return image
    }
    return nil
  }
}

extension MergeVideoViewController: UIImagePickerControllerDelegate {
  func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [String : Any]) {
    dismiss(animated: true, completion: nil)
    
    guard let mediaType = info[UIImagePickerControllerMediaType] as? String,
      mediaType == (kUTTypeMovie as String),
      let url = info[UIImagePickerControllerMediaURL] as? URL
      else { return }
    
    let avAsset = AVAsset(url: url)
    var message = ""
    if loadingAssetOne {
      message = "Video one loaded"
      firstAsset = avAsset
    } else {
      message = "Video two loaded"
      secondAsset = avAsset
    }
    assetUrl = url
    let alert = UIAlertController(title: "Asset Loaded", message: message, preferredStyle: .alert)
    alert.addAction(UIAlertAction(title: "OK", style: UIAlertActionStyle.cancel, handler: nil))
    present(alert, animated: true, completion: nil)
  }
  
}

extension MergeVideoViewController: UINavigationControllerDelegate {
  
}

extension MergeVideoViewController: MPMediaPickerControllerDelegate {
  func mediaPicker(_ mediaPicker: MPMediaPickerController, didPickMediaItems mediaItemCollection: MPMediaItemCollection) {
    
    dismiss(animated: true) {
      let selectedSongs = mediaItemCollection.items
      guard let song = selectedSongs.first else { return }
      
      let url = song.value(forProperty: MPMediaItemPropertyAssetURL) as? URL
      self.audioAsset = (url == nil) ? nil : AVAsset(url: url!)
      let title = (url == nil) ? "Asset Not Available" : "Asset Loaded"
      let message = (url == nil) ? "Audio Not Loaded" : "Audio Loaded"
      
      let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
      alert.addAction(UIAlertAction(title: "OK", style: .cancel, handler:nil))
      self.present(alert, animated: true, completion: nil)
    }
  }
  
  func mediaPickerDidCancel(_ mediaPicker: MPMediaPickerController) {
    dismiss(animated: true, completion: nil)
  }
}
