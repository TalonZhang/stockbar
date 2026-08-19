#import <AppKit/AppKit.h>

#import "StockBarAppDelegate.h"

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        StockBarAppDelegate *delegate = [[StockBarAppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
