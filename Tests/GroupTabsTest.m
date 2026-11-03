#import <AppKit/AppKit.h>
#import "GroupTabsMenuItemView.h"
#import "WatchlistStore.h"

@interface TabsPreviewBackground : NSView
@end
@implementation TabsPreviewBackground
- (void)drawRect:(NSRect)rect {
    [NSColor.windowBackgroundColor setFill];
    NSRectFill(rect);
}
@end

@interface TabTestDelegate : NSObject <GroupTabsMenuItemViewDelegate>
@property (nonatomic, strong) WatchlistStore *store;
@property (nonatomic) NSUInteger createRequests;
@property (nonatomic) NSUInteger managementRequests;
@end

@implementation TabTestDelegate
- (void)groupTabsView:(GroupTabsMenuItemView *)view didSelectGroup:(NSString *)identifier {
    [self.store selectGroup:identifier];
    [view updateGroups:self.store.groups selectedIdentifier:identifier];
}
- (void)groupTabsViewDidRequestCreate:(GroupTabsMenuItemView *)view {
    (void)view;
    self.createRequests++;
}
- (void)groupTabsViewDidRequestManagement:(GroupTabsMenuItemView *)view {
    (void)view;
    self.managementRequests++;
}
@end

static void Check(BOOL condition, NSString *message) {
    if (!condition) {
        fprintf(stderr, "%s\n", message.UTF8String);
        exit(1);
    }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *suite = [@"dev.talon.stockbar.tabs-test." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        WatchlistStore *store = [[WatchlistStore alloc] initWithDefaults:defaults];
        for (NSString *name in @[@"科技", @"医药", @"场内基金", @"长期投资观察", @"红利低波ETF", @"消费", @"一二三四五六七八九十"]) {
            Check([store createGroupWithName:name error:nil] != nil, @"Setup group creation failed");
        }
        TabTestDelegate *delegate = [[TabTestDelegate alloc] init];
        delegate.store = store;
        GroupTabsMenuItemView *view = [[GroupTabsMenuItemView alloc] initWithFrame:NSZeroRect];
        view.delegate = delegate;
        [view updateGroups:store.groups selectedIdentifier:store.selectedGroupIdentifier];
        [view layoutSubtreeIfNeeded];

        NSScrollView *scrollView = nil;
        for (NSView *subview in view.subviews) {
            Check(NSContainsRect(view.bounds, subview.frame), @"Header control outside row bounds");
            if ([subview isKindOfClass:NSScrollView.class]) {
                scrollView = (NSScrollView *)subview;
            }
        }
        Check(scrollView != nil, @"Tab scroll view missing");
        NSArray<NSView *> *buttons = scrollView.documentView.subviews;
        Check(buttons.count == store.groups.count, @"Missing group buttons");
        Check(NSWidth(scrollView.documentView.frame) > NSWidth(scrollView.bounds), @"Many groups did not produce scrollable content");
        NSButton *last = (NSButton *)buttons.lastObject;
        Check([last.title isEqualToString:@"一二三四"], @"Long tab title not abbreviated");
        Check([last.toolTip isEqualToString:@"一二三四五六七八九十"], @"Full-name tooltip missing");
        Check(NSIntersectsRect(last.frame, scrollView.documentVisibleRect), @"Active offscreen group was not scrolled into view");
        NSButton *first = (NSButton *)buttons.firstObject;
        [first performClick:nil];
        Check([store.selectedGroupIdentifier isEqualToString:WatchlistDefaultGroupIdentifier], @"Tab click did not switch groups");
        Check(scrollView.documentView.subviews.firstObject == first, @"Selection unnecessarily rebuilt button under mouse");
        Check(first.state == NSControlStateValueOn && last.state == NSControlStateValueOff, @"Tab selection styling not updated");
        for (NSView *subview in view.subviews) {
            if ([subview isKindOfClass:NSButton.class]) {
                [(NSButton *)subview performClick:nil];
            }
        }
        Check(delegate.createRequests == 1 && delegate.managementRequests == 1, @"Group toolbar actions not delivered");

        if (argc > 1) {
            TabsPreviewBackground *background = [[TabsPreviewBackground alloc] initWithFrame:view.bounds];
            [background addSubview:view];
            NSString *path = [NSString stringWithUTF8String:argv[1]];
            for (NSString *appearanceName in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
                background.appearance = [NSAppearance appearanceNamed:appearanceName];
                [background layoutSubtreeIfNeeded];
                NSBitmapImageRep *bitmap = [background bitmapImageRepForCachingDisplayInRect:background.bounds];
                [background cacheDisplayInRect:background.bounds toBitmapImageRep:bitmap];
                NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                NSString *output = [appearanceName isEqualToString:NSAppearanceNameAqua]
                    ? path : [[path stringByDeletingPathExtension] stringByAppendingString:@"-dark.png"];
                Check([png writeToFile:output atomically:YES], @"Unable to render header preview");
            }
        }
        [defaults removePersistentDomainForName:suite];
        puts("Group tabs: layout, overflow, four-character titles, switching and toolbar actions passed");
    }
    return 0;
}
