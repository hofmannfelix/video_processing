# video_manipulation

A library for manipulating videos.
This library has the following features
 * Changing a videos framerate
 * Changing a videos speed/duration
 * Adding still frames to an existing video, e.g. watermarks
 * Generate videos from images

 NOTE: Currently supports iOS only

## Install

Simply add the following line to your pubspec.yaml file:

`video_manipulation: ^0.1.7`

## Usage

The plugin currently has one static method for all video manipulation: `.generateVideo(List<String> paths, String filename, int fps, double speed)`.

Parameters
`paths` list of input file paths. Can be images (.jpg or .png) or video files (.mp4) that are used to generate the new video. E.g.: `["documents/input.mp4", "documents/watermark.jpg]` - in this case the plugin would add the "watermark.jpg" image to every frame of the "input.mp4" video. The image would be scaled to have the same size as the "input.mp4" video.

`filename` the filename of the generated video. The directory of the first input file is used as output directory.

`fps` frames per second of the output file.

`speed` a value between 0.1 (slowmotion) and 1xxx.0 (timelapse). 1.0 to keep the same speed.

The method returns the full path of the generated video when successful.

## How it works
This plugin is using AVFoundation on the iOS part to extract frames from a video and also encoding them back to an mp4 file.
Android has currently no implementation. FFmpeg won`t be implemented due to licensing, extra overhead from the ffmpeg binaries and overall slow performance.
A possible solution could be http://jcodec.org/
