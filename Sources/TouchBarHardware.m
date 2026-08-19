#import "TouchBarHardware.h"

#import <IOKit/IOKitLib.h>

@implementation TouchBarHardware

+ (BOOL)isPresent {
    // Touch Bar Macs expose the embedded OS host that drives the display.
    // Check a few observed service names so newer implementations can still
    // opt in without relying on model-number tables.
    const char *serviceClasses[] = {
        "AppleEmbeddedOSSupportHost",
        "AppleTouchBar",
        "AppleDFRDisplay"
    };

    for (NSUInteger index = 0; index < sizeof(serviceClasses) / sizeof(serviceClasses[0]); index++) {
        CFMutableDictionaryRef matching = IOServiceMatching(serviceClasses[index]);
        if (!matching) {
            continue;
        }
        io_service_t service = IOServiceGetMatchingService(kIOMasterPortDefault, matching);
        if (service != IO_OBJECT_NULL) {
            IOObjectRelease(service);
            return YES;
        }
    }
    return NO;
}

@end
