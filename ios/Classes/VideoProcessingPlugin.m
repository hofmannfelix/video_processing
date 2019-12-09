#import "VideoProcessingPlugin.h"
#import <video_processing/video_processing-Swift.h>

@implementation VideoProcessingPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftVideoProcessingPlugin registerWithRegistrar:registrar];
}
@end
