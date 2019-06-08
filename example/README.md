# video_manipulation_example

Demonstrates how to use the video_manipulation plugin.

```
void generateTimelapse() async {
    final speed = 6.0;
    final framerate = 60;
    final inputFilename = "clock.mp4";
    final outputFilename = "clock-processed.mp4";
    final docDir = (await getApplicationDocumentsDirectory()).path;
    final inputFilepath = docDir + "/" + inputFilename;

    _outputFilepath =
        await VideoManipulation.generateVideo([inputFilepath], outputFilename, framerate, speed);
}
```
