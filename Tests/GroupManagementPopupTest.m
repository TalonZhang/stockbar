#import <AppKit/AppKit.h>
#import "GroupTabsMenuItemView.h"

@interface PopupTest : NSObject <NSMenuDelegate, GroupTabsMenuItemViewDelegate>
@property (nonatomic, strong) NSMenu *parentMenu;
@property (nonatomic, strong) NSMenu *managementMenu;
@property (nonatomic, strong) GroupTabsMenuItemView *tabs;
@property (nonatomic) BOOL parentClosed;
@property (nonatomic) BOOL childOpened;
@property (nonatomic) BOOL childClosed;
@property (nonatomic) BOOL failed;
@end

@implementation PopupTest
- (void)schedule:(SEL)selector delay:(NSTimeInterval)delay {
    NSTimer *timer = [NSTimer timerWithTimeInterval:delay target:self selector:selector userInfo:nil repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSEventTrackingRunLoopMode];
}
- (void)menuWillOpen:(NSMenu *)menu {
    if (menu == self.parentMenu) {
        [self schedule:@selector(clickMore:) delay:0.15];
    } else {
        self.childOpened = YES;
        self.failed = !self.parentClosed;
        [self schedule:@selector(closeManagement:) delay:0.15];
    }
}
- (void)menuDidClose:(NSMenu *)menu {
    if (menu == self.parentMenu) {
        self.parentClosed = YES;
    } else {
        self.childClosed = YES;
    }
}
- (void)clickMore:(NSTimer *)timer {
    (void)timer;
    for (NSView *view in self.tabs.subviews) {
        if ([view isKindOfClass:NSButton.class] && [((NSButton *)view).title isEqualToString:@"⋯"]) {
            [(NSButton *)view performClick:nil];
            return;
        }
    }
    self.failed = YES;
    [self.parentMenu cancelTrackingWithoutAnimation];
}
- (void)closeManagement:(NSTimer *)timer {
    (void)timer;
    [self.managementMenu cancelTrackingWithoutAnimation];
}
- (void)timeout:(NSTimer *)timer {
    (void)timer;
    if (!self.childClosed) {
        self.failed = YES;
        [self.parentMenu cancelTrackingWithoutAnimation];
        [self.managementMenu cancelTrackingWithoutAnimation];
    }
}
- (void)groupTabsViewDidRequestManagement:(GroupTabsMenuItemView *)view {
    [view showManagementMenu:self.managementMenu];
}
- (void)groupTabsViewDidRequestCreate:(GroupTabsMenuItemView *)view { (void)view; }
- (void)groupTabsView:(GroupTabsMenuItemView *)view didSelectGroup:(NSString *)identifier {
    (void)view; (void)identifier;
}
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [NSApp finishLaunching];
        [NSApp activateIgnoringOtherApps:YES];
        PopupTest *test = [[PopupTest alloc] init];
        test.parentMenu = [[NSMenu alloc] initWithTitle:@"StockBar popup test"];
        test.parentMenu.delegate = test;
        test.tabs = [[GroupTabsMenuItemView alloc] initWithFrame:NSZeroRect];
        test.tabs.delegate = test;
        NSMenuItem *header = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
        header.view = test.tabs;
        [test.parentMenu addItem:header];
        test.managementMenu = [[NSMenu alloc] initWithTitle:@"分组管理"];
        test.managementMenu.delegate = test;
        [test.managementMenu addItemWithTitle:@"从其他分组添加" action:nil keyEquivalent:@""];
        [test.managementMenu addItemWithTitle:@"重命名当前分组…" action:nil keyEquivalent:@""];
        [test.managementMenu addItemWithTitle:@"删除当前分组…" action:nil keyEquivalent:@""];
        [test schedule:@selector(timeout:) delay:2.0];
        NSRect frame = NSScreen.mainScreen.visibleFrame;
        [test.parentMenu popUpMenuPositioningItem:nil
                                      atLocation:NSMakePoint(NSMaxX(frame) - 350.0, NSMaxY(frame) - 12.0)
                                          inView:nil];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3.0];
        while (!test.childClosed && deadline.timeIntervalSinceNow > 0.0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
        }
        if (test.failed || !test.parentClosed || !test.childOpened || !test.childClosed) {
            fprintf(stderr, "Popup failed: parentClosed=%d childOpened=%d childClosed=%d\n",
                    test.parentClosed, test.childOpened, test.childClosed);
            return 1;
        }
        puts("Management popup: parent closed first, child opened and closed successfully");
    }
    return 0;
}
