#import "VideoManipulationPlugin.h"
#import <video_manipulation/video_manipulation-Swift.h>

@implementation VideoManipulationPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftVideoManipulationPlugin registerWithRegistrar:registrar];
}
@end
