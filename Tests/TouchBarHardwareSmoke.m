#import <Foundation/Foundation.h>

#import "TouchBarHardware.h"

int main(void) {
    @autoreleasepool {
        BOOL present = [TouchBarHardware isPresent];
        NSLog(@"Touch Bar hardware: %@", present ? @"present" : @"not present");
    }
    return 0;
}
