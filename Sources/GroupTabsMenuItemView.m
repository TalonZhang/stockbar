#import "GroupTabsMenuItemView.h"
#import "WatchlistStore.h"

@interface GroupTabButton : NSButton
@end

@implementation GroupTabButton

- (void)setState:(NSControlStateValue)state {
    [super setState:state];
    self.needsDisplay = YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    BOOL selected = self.state == NSControlStateValueOn;
    NSString *appearance = [self.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    BOOL dark = [appearance isEqualToString:NSAppearanceNameDarkAqua];
    NSRect pillRect = NSInsetRect(self.bounds, 1.0, 1.0);
    NSBezierPath *pill = [NSBezierPath bezierPathWithRoundedRect:pillRect xRadius:6.0 yRadius:6.0];

    if (selected) {
        [[NSColor colorWithSRGBRed:0.38 green:0.49 blue:0.61 alpha:dark ? 0.27 : 0.14] setFill];
        [pill fill];
        [[NSColor colorWithSRGBRed:0.38 green:0.49 blue:0.61 alpha:dark ? 0.42 : 0.24] setStroke];
        pill.lineWidth = 0.7;
        [pill stroke];
    } else if (self.cell.isHighlighted) {
        [[NSColor.labelColor colorWithAlphaComponent:0.05] setFill];
        [pill fill];
    }

    NSFont *font = [NSFont systemFontOfSize:12.0 weight:selected ? NSFontWeightMedium : NSFontWeightRegular];
    NSDictionary *attributes = @{
        NSFontAttributeName: font,
        NSForegroundColorAttributeName: selected ? NSColor.labelColor : NSColor.secondaryLabelColor
    };
    NSSize textSize = [self.title sizeWithAttributes:attributes];
    NSPoint point = NSMakePoint((NSWidth(self.bounds) - textSize.width) / 2.0,
                               (NSHeight(self.bounds) - textSize.height) / 2.0);
    [self.title drawAtPoint:point withAttributes:attributes];
}

@end

@interface GroupTabsMenuItemView ()
@property (nonatomic, strong) NSScrollView *scrollView;
@property (nonatomic, strong) NSView *tabsContainer;
@property (nonatomic, strong) NSMutableArray<NSButton *> *tabButtons;
@property (nonatomic, strong, nullable) NSMenu *pendingManagementMenu;
@property (nonatomic) NSPoint managementMenuLocation;
@end

@implementation GroupTabsMenuItemView

- (instancetype)initWithFrame:(NSRect)frame {
    (void)frame;
    self = [super initWithFrame:NSMakeRect(0, 0, 326.0, 40.0)];
    if (self) {
        _tabButtons = [NSMutableArray array];
        _scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(12.0, 6.0, 244.0, 28.0)];
        _scrollView.drawsBackground = NO;
        _scrollView.hasHorizontalScroller = NO;
        _scrollView.hasVerticalScroller = NO;
        _scrollView.horizontalScrollElasticity = NSScrollElasticityAllowed;
        _scrollView.verticalScrollElasticity = NSScrollElasticityNone;
        _scrollView.toolTip = @"左右滚动查看分组，悬停查看完整名称";
        _tabsContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 244.0, 28.0)];
        _scrollView.documentView = _tabsContainer;
        [self addSubview:_scrollView];

        NSButton *create = [NSButton buttonWithTitle:@"＋" target:self action:@selector(createGroup:)];
        create.frame = NSMakeRect(261.0, 7.0, 25.0, 26.0);
        create.bordered = NO;
        create.font = [NSFont systemFontOfSize:18.0];
        create.toolTip = @"新建分组（名称最多 10 个字）";
        create.accessibilityLabel = @"新建分组";
        [self addSubview:create];

        NSButton *manage = [NSButton buttonWithTitle:@"⋯" target:self action:@selector(manageGroup:)];
        manage.frame = NSMakeRect(290.0, 7.0, 25.0, 26.0);
        manage.bordered = NO;
        manage.font = [NSFont systemFontOfSize:18.0];
        manage.toolTip = @"分组管理：添加已有自选、重命名、删除";
        manage.accessibilityLabel = @"分组管理";
        [self addSubview:manage];
    }
    return self;
}

- (void)updateGroups:(NSArray<WatchlistGroup *> *)groups selectedIdentifier:(NSString *)identifier {
    BOOL unchanged = groups.count == self.tabButtons.count;
    for (NSUInteger index = 0; unchanged && index < groups.count; index++) {
        NSButton *button = self.tabButtons[index];
        unchanged = [button.identifier isEqualToString:groups[index].identifier]
            && [button.toolTip isEqualToString:groups[index].name];
    }
    if (unchanged) {
        [self updateSelection:identifier];
        return;
    }
    for (NSButton *button in self.tabButtons) {
        [button removeFromSuperview];
    }
    [self.tabButtons removeAllObjects];
    CGFloat position = 0.0;
    for (WatchlistGroup *group in groups) {
        NSString *title = [WatchlistStore displayNameForGroupName:group.name];
        NSButton *button = [GroupTabButton buttonWithTitle:title target:self action:@selector(selectGroup:)];
        button.bordered = NO;
        button.font = [NSFont systemFontOfSize:12.0 weight:NSFontWeightMedium];
        CGFloat width = [title sizeWithAttributes:@{NSFontAttributeName: button.font}].width + 22.0;
        if (width < 45.0) {
            width = 45.0;
        }
        button.frame = NSMakeRect(position, 1.0, width, 26.0);
        button.toolTip = group.name;
        button.accessibilityLabel = group.name;
        button.identifier = group.identifier;
        [self.tabsContainer addSubview:button];
        [self.tabButtons addObject:button];
        position += width + 4.0;
    }
    CGFloat totalWidth = position > NSWidth(self.scrollView.bounds) ? position : NSWidth(self.scrollView.bounds);
    self.tabsContainer.frame = NSMakeRect(0, 0, totalWidth, 28.0);
    [self updateSelection:identifier];
}

- (void)updateSelection:(NSString *)identifier {
    for (NSButton *button in self.tabButtons) {
        BOOL selected = [button.identifier isEqualToString:identifier];
        button.state = selected ? NSControlStateValueOn : NSControlStateValueOff;
        [button displayIfNeeded];
        if (selected) {
            [self.tabsContainer scrollRectToVisible:button.frame];
        }
    }
}

- (void)selectGroup:(NSButton *)sender {
    [self.delegate groupTabsView:self didSelectGroup:sender.identifier];
}

- (void)createGroup:(id)sender {
    (void)sender;
    [self.delegate groupTabsViewDidRequestCreate:self];
}

- (void)manageGroup:(id)sender {
    (void)sender;
    [self.delegate groupTabsViewDidRequestManagement:self];
}

- (void)showManagementMenu:(NSMenu *)menu {
    // AppKit cannot begin tracking an unrelated popup while the containing
    // menu is still tracking. Capture the screen anchor before it disappears,
    // then present in the default run-loop mode after the parent has closed.
    NSPoint windowLocation = [self convertPoint:NSMakePoint(210.0, 0.0) toView:nil];
    self.managementMenuLocation = [self.window convertPointToScreen:windowLocation];
    self.pendingManagementMenu = menu;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(presentManagementMenu) object:nil];
    [self.enclosingMenuItem.menu cancelTrackingWithoutAnimation];
    [self performSelector:@selector(presentManagementMenu) withObject:nil afterDelay:0.05];
}

- (void)presentManagementMenu {
    NSMenu *menu = self.pendingManagementMenu;
    self.pendingManagementMenu = nil;
    if (menu) {
        [menu popUpMenuPositioningItem:nil atLocation:self.managementMenuLocation inView:nil];
    }
}

@end
