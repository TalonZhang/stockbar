#import "StockBarAppDelegate.h"

#import "AddStockMenuItemView.h"
#import "GroupTabsMenuItemView.h"
#import "LoginItemController.h"
#import "PersistentTouchBarController.h"
#import "StockMenuItemView.h"
#import "StockQuote.h"
#import "StockSearchWindowController.h"
#import "TencentQuoteService.h"
#import "TouchBarHardware.h"
#import "WatchlistStore.h"

static NSString * const LegacyBundleIdentifier = @"dev.touchbarstocks.prototype";
static NSString * const LegacyMigrationKey = @"migration.touchbarstocks.v1";
static NSString * const WatchlistDefaultsKey = @"watchlist.codes.v1";
static NSString * const QuoteSourceDefaultsKey = @"quote.source.v1";
static NSString * const RightSidePositionSeededKey = @"status.rightSideDefault.v1";

@interface StockBarAppDelegate () <StockMenuItemViewDelegate, AddStockMenuItemViewDelegate, GroupTabsMenuItemViewDelegate, StockSearchWindowControllerDelegate>

@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSMenu *statusMenu;
@property (nonatomic, strong) NSMenuItem *quoteStatusMenuItem;
@property (nonatomic, strong) NSMutableArray<NSMenuItem *> *stockMenuItems;
@property (nonatomic, strong) AddStockMenuItemView *addStockView;
@property (nonatomic, strong) GroupTabsMenuItemView *groupTabsView;
@property (nonatomic, strong) NSMenuItem *emptyGroupMenuItem;
@property (nonatomic, strong) NSMenuItem *quoteSourceMenuItem;
@property (nonatomic, strong) NSMenuItem *loginItemMenuItem;
@property (nonatomic, strong, nullable) NSMenuItem *touchBarStatusMenuItem;
@property (nonatomic, strong, nullable) NSMenuItem *persistenceMenuItem;
@property (nonatomic, strong, nullable) NSMenuItem *trayVisibilityMenuItem;

@property (nonatomic, strong) WatchlistStore *watchlistStore;
@property (nonatomic, strong) TencentQuoteService *quoteService;
@property (nonatomic, strong) LoginItemController *loginItemController;
@property (nonatomic, strong, nullable) PersistentTouchBarController *touchBarController;
@property (nonatomic, copy) NSArray<StockQuote *> *latestQuotes;
@property (nonatomic, strong) NSMutableDictionary<NSString *, StockQuote *> *quotesByCode;
@property (nonatomic, strong, nullable) NSTimer *watchdogTimer;
@property (nonatomic) BOOL touchBarFeatureAvailable;
@property (nonatomic, copy, nullable) NSString *draggedStockCode;
@property (nonatomic, copy, nullable) NSString *draggedGroupIdentifier;
@property (nonatomic) NSInteger proposedDropIndex;
@property (nonatomic) BOOL quoteMenuIsTracking;
@property (nonatomic, strong, nullable) StockSearchWindowController *stockSearchController;
@property (nonatomic) NSUInteger stockSearchContext;
@property (nonatomic, copy, nullable) NSDictionary *pendingStockSearchContext;

@end

@implementation StockBarAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    [self migrateLegacyPreferencesIfNeeded];
    self.watchlistStore = [[WatchlistStore alloc] init];
    self.quoteService = [[TencentQuoteService alloc] initWithCodes:[self quoteCodes]];
    self.loginItemController = [[LoginItemController alloc] init];
    self.latestQuotes = [self placeholderQuotesForCodes:[self displayedQuoteCodes]];
    self.quotesByCode = [NSMutableDictionary dictionary];
    self.stockMenuItems = [NSMutableArray array];

    if ([TouchBarHardware isPresent]) {
        PersistentTouchBarController *controller = [[PersistentTouchBarController alloc] init];
        if (controller.isAvailable) {
            self.touchBarController = controller;
            self.touchBarFeatureAvailable = YES;
        }
    }

    NSError *loginItemRepairError = nil;
    if (![self.loginItemController repairRegistrationIfNeededWithError:&loginItemRepairError]) {
        NSLog(@"登录项路径迁移失败：%@", loginItemRepairError);
    }

    [self buildStatusItem];
    [self observeSystemLifecycle];

    __weak StockBarAppDelegate *weakSelf = self;
    self.quoteService.updateHandler = ^(NSArray<StockQuote *> *quotes, NSString *statusText) {
        StockBarAppDelegate *strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        for (StockQuote *quote in quotes) {
            if (quote.isAvailable || !strongSelf.quotesByCode[quote.code]) {
                strongSelf.quotesByCode[quote.code] = quote;
            }
        }
        strongSelf.quoteStatusMenuItem.title = statusText;
        [strongSelf refreshDisplayedQuotes];
    };
    [self.quoteService start];
    [self.touchBarController present];
    [self updateMenuState];

    if (self.touchBarFeatureAvailable) {
        self.watchdogTimer = [NSTimer timerWithTimeInterval:3.0
                                                     target:self
                                                   selector:@selector(watchdogTick:)
                                                   userInfo:nil
                                                    repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:self.watchdogTimer forMode:NSRunLoopCommonModes];
    }
}

- (NSArray<NSString *> *)quoteCodes {
    NSMutableArray<NSString *> *codes = [NSMutableArray arrayWithObject:QuoteCodeSSECompositeIndex];
    [codes addObjectsFromArray:self.watchlistStore.allCodes];
    return codes;
}

- (NSArray<NSString *> *)displayedQuoteCodes {
    NSMutableArray<NSString *> *codes = [NSMutableArray arrayWithObject:QuoteCodeSSECompositeIndex];
    [codes addObjectsFromArray:self.watchlistStore.codes];
    return codes;
}

- (void)refreshDisplayedQuotes {
    NSMutableArray<StockQuote *> *quotes = [NSMutableArray array];
    for (NSString *code in [self displayedQuoteCodes]) {
        StockQuote *quote = self.quotesByCode[code];
        if (!quote || ([code isEqualToString:QuoteCodeSSECompositeIndex] && !quote.isAvailable)) {
            quote = [self placeholderQuotesForCodes:@[code]].firstObject;
        }
        [quotes addObject:quote];
    }
    self.latestQuotes = quotes;
    [self.touchBarController updateQuotes:quotes];
    [self updateStatusTooltip];
    [self updateStockRows];
}

- (void)refreshAfterGroupChange {
    [self.groupTabsView updateGroups:self.watchlistStore.groups selectedIdentifier:self.watchlistStore.selectedGroupIdentifier];
    NSArray *codes = [self quoteCodes];
    if (![codes isEqualToArray:self.quoteService.codes]) {
        [self.quoteService setCodes:codes];
        [self.quoteService refresh];
    }
    [self refreshDisplayedQuotes];
}

- (NSArray<StockQuote *> *)placeholderQuotesForCodes:(NSArray<NSString *> *)codes {
    NSMutableArray<StockQuote *> *quotes = [NSMutableArray arrayWithCapacity:codes.count];
    for (NSString *code in codes) {
        NSString *name = [code isEqualToString:QuoteCodeSSECompositeIndex] ? @"上证指数" : code;
        StockQuote *quote = [[StockQuote alloc] initWithName:name code:code previousClose:0.0 price:0.0];
        quote.available = NO;
        [quotes addObject:quote];
    }
    return quotes;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [self.watchdogTimer invalidate];
    [self.quoteService stop];
    [self.touchBarController stop];
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender {
    (void)sender;
    return NO;
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
    (void)sender;
    (void)flag;
    self.statusItem.visible = YES;
    return NO;
}

+ (void)seedRightSidePositionInDefaults:(NSUserDefaults *)defaults {
    if ([defaults boolForKey:RightSidePositionSeededKey]) {
        return;
    }
    // AppKit autosave positions are distances from the right edge. This is a
    // best-effort preference, not a public placement guarantee. Seed once,
    // before item creation, then leave subsequent user positioning alone.
    [defaults setDouble:1.0 forKey:@"NSStatusItem Preferred Position StockBar"];
    [defaults setDouble:1.0 forKey:@"NSStatusItem Preferred Position Item-0"];
    [defaults setBool:YES forKey:RightSidePositionSeededKey];
}

- (void)showMenuAfterReopen {
    if (!self.statusMenu || self.quoteMenuIsTracking) {
        return;
    }
    [self updateMenuState];
    NSScreen *screen = NSScreen.mainScreen;
    if (!screen) {
        return;
    }
    NSRect visibleFrame = screen.visibleFrame;
    NSPoint location = NSMakePoint(NSMaxX(visibleFrame) - self.statusMenu.size.width - 12.0,
                                  NSMaxY(visibleFrame) - 2.0);
    NSLog(@"StockBar reopened: presenting quote menu");
    [self.statusMenu popUpMenuPositioningItem:nil atLocation:location inView:nil];
}

- (void)logStatusItemState {
    NSStatusBarButton *button = self.statusItem.button;
    NSRect frame = button.window.frame;
    CGFloat rightGap = NSMaxX(button.window.screen.frame) - NSMaxX(frame);
    NSLog(@"StockBar status item: visible=%d button=%d image=%d x=%.0f y=%.0f width=%.0f height=%.0f rightGap=%.0f menuOpen=%d searchOpen=%d",
          self.statusItem.isVisible, button != nil, button.image != nil,
          frame.origin.x, frame.origin.y, frame.size.width, frame.size.height,
          rightGap, self.quoteMenuIsTracking, self.stockSearchController.window.isVisible);
}

- (void)migrateLegacyPreferencesIfNeeded {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults boolForKey:LegacyMigrationKey]) {
        return;
    }

    NSDictionary *legacy = [defaults persistentDomainForName:LegacyBundleIdentifier];
    id legacyCodes = legacy[WatchlistDefaultsKey];
    id legacySource = legacy[QuoteSourceDefaultsKey];
    if (![defaults objectForKey:WatchlistDefaultsKey] && [legacyCodes isKindOfClass:NSArray.class]) {
        [defaults setObject:legacyCodes forKey:WatchlistDefaultsKey];
    }
    if (![defaults objectForKey:QuoteSourceDefaultsKey] && [legacySource respondsToSelector:@selector(integerValue)]) {
        [defaults setObject:legacySource forKey:QuoteSourceDefaultsKey];
    }
    [defaults setBool:YES forKey:LegacyMigrationKey];
}

- (void)buildStatusItem {
    [StockBarAppDelegate seedRightSidePositionInDefaults:NSUserDefaults.standardUserDefaults];
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.autosaveName = @"StockBar";
    self.statusItem.visible = YES;
    self.statusItem.button.toolTip = @"StockBar · 股票与场内基金行情";
    if (@available(macOS 11.0, *)) {
        NSImage *image = [NSImage imageWithSystemSymbolName:@"chart.line.uptrend.xyaxis"
                                   accessibilityDescription:@"StockBar"];
        if (image) {
            image.size = NSMakeSize(18.0, 18.0);
            image.template = YES;
            self.statusItem.button.image = image;
            self.statusItem.button.imagePosition = NSImageOnly;
        }
    }
    if (!self.statusItem.button.image) {
        self.statusItem.button.title = @"股";
        self.statusItem.button.imagePosition = NSNoImage;
    }

    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"StockBar"];
    menu.delegate = self;
    self.statusMenu = menu;

    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (version.length == 0) {
        version = @"";
    }
    NSMenuItem *titleItem = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"StockBar · %@", version]
                                                     action:nil
                                              keyEquivalent:@""];
    titleItem.enabled = NO;
    [menu addItem:titleItem];

    NSMenuItem *tabsItem = [[NSMenuItem alloc] initWithTitle:@"分组" action:nil keyEquivalent:@""];
    self.groupTabsView = [[GroupTabsMenuItemView alloc] initWithFrame:NSZeroRect];
    self.groupTabsView.delegate = self;
    [self.groupTabsView updateGroups:self.watchlistStore.groups selectedIdentifier:self.watchlistStore.selectedGroupIdentifier];
    tabsItem.view = self.groupTabsView;
    [menu addItem:tabsItem];

    self.quoteStatusMenuItem = [[NSMenuItem alloc] initWithTitle:@"正在获取行情…" action:nil keyEquivalent:@""];
    self.quoteStatusMenuItem.enabled = NO;
    [menu addItem:self.quoteStatusMenuItem];

    [self rebuildStockRows];
    self.emptyGroupMenuItem = [[NSMenuItem alloc] initWithTitle:@"本组暂无自选，点击下方按钮添加" action:nil keyEquivalent:@""];
    self.emptyGroupMenuItem.enabled = NO;
    self.emptyGroupMenuItem.hidden = self.watchlistStore.codes.count > 0;
    [menu addItem:self.emptyGroupMenuItem];
    [menu addItem:NSMenuItem.separatorItem];

    NSMenuItem *addItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    self.addStockView = [[AddStockMenuItemView alloc] initWithFrame:NSZeroRect];
    self.addStockView.delegate = self;
    addItem.view = self.addStockView;
    addItem.enabled = YES;
    [menu addItem:addItem];

    self.quoteSourceMenuItem = [[NSMenuItem alloc] initWithTitle:@"行情源" action:nil keyEquivalent:@""];
    self.quoteSourceMenuItem.submenu = [[NSMenu alloc] initWithTitle:@"行情源"];
    for (NSInteger source = QuoteSourceAutomatic; source <= QuoteSourceEastmoney; source++) {
        NSMenuItem *sourceItem = [[NSMenuItem alloc] initWithTitle:[TencentQuoteService displayNameForSource:(QuoteSource)source]
                                                           action:@selector(selectQuoteSource:)
                                                    keyEquivalent:@""];
        sourceItem.target = self;
        sourceItem.tag = source;
        [self.quoteSourceMenuItem.submenu addItem:sourceItem];
    }
    [menu addItem:self.quoteSourceMenuItem];

    NSMenuItem *refreshItem = [[NSMenuItem alloc] initWithTitle:@"立即刷新行情" action:@selector(refreshQuotes:) keyEquivalent:@"r"];
    refreshItem.target = self;
    [menu addItem:refreshItem];

    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *newsItem = [[NSMenuItem alloc] initWithTitle:@"财经快讯（东方财富）"
                                                    action:@selector(openFinancialNews:)
                                             keyEquivalent:@""];
    newsItem.target = self;
    newsItem.toolTip = @"在默认浏览器打开东方财富全球财经快讯";
    [menu addItem:newsItem];

    if (self.touchBarFeatureAvailable) {
        [menu addItem:NSMenuItem.separatorItem];
        self.touchBarStatusMenuItem = [[NSMenuItem alloc] initWithTitle:self.touchBarController.diagnosticText
                                                                 action:nil
                                                          keyEquivalent:@""];
        self.touchBarStatusMenuItem.enabled = NO;
        [menu addItem:self.touchBarStatusMenuItem];

        self.persistenceMenuItem = [[NSMenuItem alloc] initWithTitle:@"显示 Touch Bar"
                                                              action:@selector(toggleTouchBar:)
                                                       keyEquivalent:@""];
        self.persistenceMenuItem.target = self;
        [menu addItem:self.persistenceMenuItem];

        self.trayVisibilityMenuItem = [[NSMenuItem alloc] initWithTitle:@"显示右侧恢复按钮"
                                                                 action:@selector(toggleTrayVisibility:)
                                                          keyEquivalent:@""];
        self.trayVisibilityMenuItem.target = self;
        [menu addItem:self.trayVisibilityMenuItem];
    }

    [menu addItem:NSMenuItem.separatorItem];
    self.loginItemMenuItem = [[NSMenuItem alloc] initWithTitle:@"开机启动" action:@selector(toggleLoginItem:) keyEquivalent:@""];
    self.loginItemMenuItem.target = self;
    [menu addItem:self.loginItemMenuItem];

    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:@"退出 StockBar" action:@selector(quit:) keyEquivalent:@"q"];
    quitItem.target = self;
    [menu addItem:quitItem];

    self.statusItem.menu = menu;
    [self performSelector:@selector(logStatusItemState) withObject:nil afterDelay:1.0];
}

- (void)observeSystemLifecycle {
    NSNotificationCenter *workspaceCenter = NSWorkspace.sharedWorkspace.notificationCenter;
    [workspaceCenter addObserver:self selector:@selector(systemDidResume:) name:NSWorkspaceDidWakeNotification object:nil];
    [workspaceCenter addObserver:self selector:@selector(systemDidResume:) name:NSWorkspaceSessionDidBecomeActiveNotification object:nil];
}

- (void)systemDidResume:(NSNotification *)notification {
    (void)notification;
    if (self.touchBarController.wantsPersistentPresentation) {
        [self.touchBarController present];
    }
    [self.quoteService refresh];
}

- (void)watchdogTick:(NSTimer *)timer {
    (void)timer;
    [self.touchBarController restoreIfNeeded];
}

- (void)menuWillOpen:(NSMenu *)menu {
    (void)menu;
    self.quoteMenuIsTracking = YES;
    [self.touchBarController restoreIfNeeded];
    [self updateMenuState];
    NSTimer *verificationTimer = [NSTimer timerWithTimeInterval:0.5
                                                        target:self
                                                      selector:@selector(logQuoteMenuState:)
                                                      userInfo:nil
                                                       repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:verificationTimer forMode:NSEventTrackingRunLoopMode];
}

- (void)menuDidClose:(NSMenu *)menu {
    (void)menu;
    self.quoteMenuIsTracking = NO;
}

- (void)logQuoteMenuState:(NSTimer *)timer {
    (void)timer;
    NSWindow *window = self.stockMenuItems.firstObject.view.window;
    NSLog(@"StockBar quote menu: windowVisible=%d rows=%lu",
          window.isVisible, (unsigned long)self.stockMenuItems.count);
}

- (void)updateStatusTooltip {
    if (self.latestQuotes.count == 0) {
        self.statusItem.button.toolTip = @"StockBar · 暂无行情";
        return;
    }
    StockQuote *quote = self.latestQuotes.firstObject;
    self.statusItem.button.toolTip = quote.isAvailable
        ? [NSString stringWithFormat:@"%@  %+.2f%%  ¥%@", quote.name, quote.percentChange, quote.formattedPrice]
        : @"StockBar · 行情暂不可用";
}

- (void)updateMenuState {
    [self.loginItemController refreshStatus];
    self.loginItemMenuItem.enabled = self.loginItemController.isAvailable;
    self.loginItemMenuItem.state = self.loginItemController.isEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    self.loginItemMenuItem.title = self.loginItemController.requiresApproval
        ? @"开机启动（等待批准）"
        : @"开机启动";

    self.quoteSourceMenuItem.title = [NSString stringWithFormat:@"行情源：%@",
        [TencentQuoteService displayNameForSource:self.quoteService.source]];
    for (NSMenuItem *item in self.quoteSourceMenuItem.submenu.itemArray) {
        item.state = item.tag == self.quoteService.source ? NSControlStateValueOn : NSControlStateValueOff;
    }

    if (self.touchBarFeatureAvailable) {
        self.touchBarStatusMenuItem.title = self.touchBarController.diagnosticText;
        self.persistenceMenuItem.state = self.touchBarController.wantsPersistentPresentation
            ? NSControlStateValueOn
            : NSControlStateValueOff;
        self.trayVisibilityMenuItem.state = self.touchBarController.trayItemVisible
            ? NSControlStateValueOn
            : NSControlStateValueOff;
    }

    [self updateStockRows];
}

- (void)updateStockRows {
    if (!self.statusMenu || !self.quoteStatusMenuItem) {
        return;
    }
    self.emptyGroupMenuItem.hidden = self.watchlistStore.codes.count > 0;

    BOOL structureMatches = self.stockMenuItems.count == self.latestQuotes.count;
    if (structureMatches) {
        for (NSUInteger index = 0; index < self.latestQuotes.count; index++) {
            StockQuote *quote = self.latestQuotes[index];
            NSMenuItem *item = self.stockMenuItems[index];
            if (![item.representedObject isEqualToString:quote.code]
                || ![item.view isKindOfClass:StockMenuItemView.class]) {
                structureMatches = NO;
                break;
            }
        }
    }

    if (!structureMatches) {
        [self rebuildStockRows];
        return;
    }

    for (NSUInteger index = 0; index < self.latestQuotes.count; index++) {
        StockMenuItemView *view = (StockMenuItemView *)self.stockMenuItems[index].view;
        [view updateWithQuote:self.latestQuotes[index]];
    }
}

- (void)rebuildStockRows {
    if (!self.statusMenu || !self.quoteStatusMenuItem) {
        return;
    }
    for (NSMenuItem *item in self.stockMenuItems) {
        [self.statusMenu removeItem:item];
    }
    [self.stockMenuItems removeAllObjects];

    NSInteger insertionIndex = [self.statusMenu indexOfItem:self.quoteStatusMenuItem] + 1;

    for (StockQuote *quote in self.latestQuotes) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
        item.representedObject = quote.code;
        StockMenuItemView *view = [[StockMenuItemView alloc] initWithQuote:quote];
        view.draggable = ![quote.code isEqualToString:QuoteCodeSSECompositeIndex];
        view.deletable = view.isDraggable;
        view.delegate = self;
        item.enabled = view.isDraggable;
        item.view = view;
        [self.statusMenu insertItem:item atIndex:insertionIndex++];
        [self.stockMenuItems addObject:item];
    }
}

- (void)stockMenuItemViewDidRequestDelete:(StockMenuItemView *)view {
    NSString *code = view.stockCode;
    if (code.length == 0 || [code isEqualToString:QuoteCodeSSECompositeIndex]) {
        return;
    }
    NSString *groupIdentifier = self.watchlistStore.selectedGroupIdentifier;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (![self.watchlistStore.selectedGroupIdentifier isEqualToString:groupIdentifier]) {
            return;
        }
        if ([self.watchlistStore removeCode:code]) {
            [self refreshAfterGroupChange];
        }
    });
}

- (void)stockMenuItemViewDidBeginDragging:(StockMenuItemView *)view {
    self.draggedStockCode = view.stockCode;
    self.draggedGroupIdentifier = self.watchlistStore.selectedGroupIdentifier;
    self.proposedDropIndex = NSNotFound;
}

- (void)stockMenuItemView:(StockMenuItemView *)view draggedToScreenPoint:(NSPoint)point {
    (void)view;
    NSArray<NSMenuItem *> *movableItems = self.stockMenuItems.count > 1
        ? [self.stockMenuItems subarrayWithRange:NSMakeRange(1, self.stockMenuItems.count - 1)]
        : @[];
    if (movableItems.count == 0) {
        return;
    }

    NSInteger closestIndex = 0;
    CGFloat closestDistance = CGFLOAT_MAX;
    for (NSUInteger index = 0; index < movableItems.count; index++) {
        StockMenuItemView *candidate = (StockMenuItemView *)movableItems[index].view;
        NSRect windowRect = [candidate convertRect:candidate.bounds toView:nil];
        NSRect screenRect = [candidate.window convertRectToScreen:windowRect];
        CGFloat distance = fabs(point.y - NSMidY(screenRect));
        if (distance < closestDistance) {
            closestDistance = distance;
            closestIndex = (NSInteger)index;
        }
        candidate.dropTarget = NO;
    }

    self.proposedDropIndex = closestIndex;
    StockMenuItemView *target = (StockMenuItemView *)movableItems[(NSUInteger)closestIndex].view;
    target.dropTarget = YES;
}

- (void)stockMenuItemViewDidEndDragging:(StockMenuItemView *)view {
    (void)view;
    for (NSMenuItem *item in self.stockMenuItems) {
        if ([item.view isKindOfClass:StockMenuItemView.class]) {
            ((StockMenuItemView *)item.view).dropTarget = NO;
        }
    }

    NSString *code = self.draggedStockCode;
    NSString *groupIdentifier = self.draggedGroupIdentifier;
    NSInteger targetIndex = self.proposedDropIndex;
    self.draggedStockCode = nil;
    self.draggedGroupIdentifier = nil;
    self.proposedDropIndex = NSNotFound;
    if (code.length == 0 || targetIndex == NSNotFound || targetIndex < 0) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (![self.watchlistStore.selectedGroupIdentifier isEqualToString:groupIdentifier]) {
            return;
        }
        if ([self.watchlistStore moveCode:code toIndex:(NSUInteger)targetIndex]) {
            [self refreshAfterGroupChange];
        }
    });
}

- (void)refreshQuotes:(id)sender {
    (void)sender;
    self.quoteStatusMenuItem.title = @"正在刷新行情…";
    [self.quoteService refresh];
}

- (void)openFinancialNews:(id)sender {
    (void)sender;
    [self.statusMenu cancelTracking];
    NSURL *url = [NSURL URLWithString:@"https://kuaixun.eastmoney.com/"];
    if (![[NSWorkspace sharedWorkspace] openURL:url]) {
        [self showErrorWithTitle:@"无法打开浏览器"
                         message:@"请在浏览器中打开 https://kuaixun.eastmoney.com/ 查看财经快讯。"];
    }
}

- (void)addStockMenuItemView:(AddStockMenuItemView *)view didSubmitInput:(NSString *)input {
    NSString *code = [WatchlistStore normalizedCodeFromInput:input];
    if (!code) {
        [self queueStockSearchFromView:view query:input submitImmediately:YES];
        return;
    }
    if ([self.watchlistStore containsCode:code]) {
        [self showErrorWithTitle:@"已经添加" message:[NSString stringWithFormat:@"%@ 已在当前分组中。", code]];
        [view focusAndSelectInput];
        return;
    }

    [view setValidating:YES];
    NSString *targetGroupIdentifier = self.watchlistStore.selectedGroupIdentifier;
    self.quoteStatusMenuItem.title = [NSString stringWithFormat:@"正在验证 %@…", code];
    __weak StockBarAppDelegate *weakSelf = self;
    [self.quoteService validateCode:code completion:^(StockQuote *quote, NSError *error) {
        StockBarAppDelegate *strongSelf = weakSelf;
        if (!quote || error) {
            [view setValidating:NO];
            [strongSelf showErrorWithTitle:@"无法添加自选"
                                   message:error.localizedDescription.length > 0
                ? error.localizedDescription
                : @"行情源没有返回该股票或场内基金。"];
            [view focusAndSelectInput];
            return;
        }
        if ([strongSelf.watchlistStore addCode:code toGroup:targetGroupIdentifier]) {
            [view clearInput];
            strongSelf.quotesByCode[code] = quote;
            [strongSelf refreshAfterGroupChange];
        } else {
            [view setValidating:NO];
        }
    }];
}

- (void)addStockMenuItemViewDidRequestEditing:(AddStockMenuItemView *)view {
    [self queueStockSearchFromView:view query:@"" submitImmediately:NO];
}

- (void)queueStockSearchFromView:(AddStockMenuItemView *)view query:(NSString *)query submitImmediately:(BOOL)submit {
    NSRect anchor = [view convertRect:view.bounds toView:nil];
    anchor = [view.window convertRectToScreen:anchor];
    NSDictionary *context = @{
        @"query": query,
        @"group": self.watchlistStore.selectedGroupIdentifier,
        @"name": self.watchlistStore.selectedGroupName,
        @"anchor": [NSValue valueWithRect:anchor],
        @"submit": @(submit)
    };
    [self.statusMenu cancelTrackingWithoutAnimation];
    if (self.pendingStockSearchContext) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(showStockSearch:) object:self.pendingStockSearchContext];
    }
    self.pendingStockSearchContext = context;
    [self performSelector:@selector(showStockSearch:) withObject:context afterDelay:0.05];
}

- (void)showStockSearch:(NSDictionary *)context {
    if (self.pendingStockSearchContext != context) {
        return;
    }
    self.pendingStockSearchContext = nil;
    self.stockSearchContext++;
    if (!self.stockSearchController) {
        self.stockSearchController = [[StockSearchWindowController alloc] init];
        self.stockSearchController.delegate = self;
    }
    [self.stockSearchController showQuery:context[@"query"] groupIdentifier:context[@"group"]
                               groupName:context[@"name"] anchorRect:[context[@"anchor"] rectValue]
                       submitImmediately:[context[@"submit"] boolValue]];
}

- (void)stockSearchController:(StockSearchWindowController *)controller
             didChooseResult:(StockSearchResult *)result
             groupIdentifier:(NSString *)groupIdentifier
                  completion:(SearchAddCompletion)completion {
    WatchlistGroup *targetGroup = nil;
    for (WatchlistGroup *group in self.watchlistStore.groups) {
        if ([group.identifier isEqualToString:groupIdentifier]) {
            targetGroup = group;
            break;
        }
    }
    NSString *message = nil;
    if (!targetGroup) {
        message = @"目标分组已删除，请关闭搜索后重新选择分组。";
    } else if ([targetGroup.codes containsObject:result.code]) {
        message = @"该标的已在分组中，请更换搜索内容。";
    }
    if (message) {
        completion([NSError errorWithDomain:@"dev.talon.stockbar.search" code:2 userInfo:@{NSLocalizedDescriptionKey: message}]);
        return;
    }

    NSUInteger context = self.stockSearchContext;
    [self.quoteService validateCode:result.code completion:^(StockQuote *quote, NSError *error) {
        if (context != self.stockSearchContext || !controller.window.isVisible) {
            completion([NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]);
            return;
        }
        if (error || !quote.isAvailable) {
            completion(error ? error : [NSError errorWithDomain:@"dev.talon.stockbar.search" code:3
                                                       userInfo:@{NSLocalizedDescriptionKey: @"未获取到有效行情，请稍后重试。"}]);
            return;
        }
        if (![self.watchlistStore addCode:result.code toGroup:groupIdentifier]) {
            completion([NSError errorWithDomain:@"dev.talon.stockbar.search" code:4
                                       userInfo:@{NSLocalizedDescriptionKey: @"未能添加：分组已变化或已包含该代码。"}]);
            return;
        }
        [self.addStockView clearInput];
        self.quotesByCode[result.code] = quote;
        [self refreshAfterGroupChange];
        completion(nil);
        [self performSelector:@selector(showMenuAfterReopen) withObject:nil afterDelay:0.05];
    }];
}

- (void)selectQuoteSource:(NSMenuItem *)menuItem {
    self.quoteService.source = (QuoteSource)menuItem.tag;
    self.quoteStatusMenuItem.title = [NSString stringWithFormat:@"正在切换到 %@…",
        [TencentQuoteService displayNameForSource:self.quoteService.source]];
    [self updateMenuState];
}

- (void)groupTabsView:(GroupTabsMenuItemView *)view didSelectGroup:(NSString *)identifier {
    (void)view;
    if ([self.watchlistStore selectGroup:identifier]) {
        [self refreshAfterGroupChange];
    }
}

- (void)groupTabsViewDidRequestCreate:(GroupTabsMenuItemView *)view {
    (void)view;
    [self.statusMenu cancelTracking];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self editGroupName:nil];
    });
}

- (void)groupTabsViewDidRequestManagement:(GroupTabsMenuItemView *)view {
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"分组管理"];
    menu.autoenablesItems = NO;
    NSString *groupIdentifier = self.watchlistStore.selectedGroupIdentifier;

    NSMenuItem *addExisting = [[NSMenuItem alloc] initWithTitle:@"从其他分组添加" action:nil keyEquivalent:@""];
    NSMenu *existingMenu = [[NSMenu alloc] initWithTitle:@"从其他分组添加"];
    for (NSString *code in self.watchlistStore.allCodes) {
        if ([self.watchlistStore containsCode:code]) {
            continue;
        }
        StockQuote *quote = self.quotesByCode[code];
        NSString *name = quote.name.length > 0 ? quote.name : code;
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:[NSString stringWithFormat:@"%@  %@", name, code]
                                                     action:@selector(addExistingToGroup:)
                                              keyEquivalent:@""];
        item.target = self;
        item.representedObject = @{@"code": code, @"group": groupIdentifier};
        [existingMenu addItem:item];
    }
    addExisting.enabled = existingMenu.numberOfItems > 0;
    addExisting.submenu = existingMenu;
    [menu addItem:addExisting];
    [menu addItem:NSMenuItem.separatorItem];

    BOOL isDefault = [groupIdentifier isEqualToString:WatchlistDefaultGroupIdentifier];
    NSMenuItem *rename = [[NSMenuItem alloc] initWithTitle:@"重命名当前分组…" action:@selector(renameSelectedGroup:) keyEquivalent:@""];
    rename.target = self;
    rename.enabled = !isDefault;
    rename.representedObject = groupIdentifier;
    [menu addItem:rename];

    NSMenuItem *remove = [[NSMenuItem alloc] initWithTitle:@"删除当前分组…" action:@selector(deleteSelectedGroup:) keyEquivalent:@""];
    remove.target = self;
    remove.enabled = !isDefault;
    remove.representedObject = groupIdentifier;
    [menu addItem:remove];
    [view showManagementMenu:menu];
}

- (void)addExistingToGroup:(NSMenuItem *)item {
    NSDictionary *selection = item.representedObject;
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.watchlistStore addCode:selection[@"code"] toGroup:selection[@"group"]]) {
            [self refreshAfterGroupChange];
            [self performSelector:@selector(showMenuAfterReopen) withObject:nil afterDelay:0.05];
        }
    });
}

- (void)renameSelectedGroup:(NSMenuItem *)item {
    NSString *identifier = item.representedObject;
    [self.statusMenu cancelTracking];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self editGroupName:identifier];
    });
}

- (void)editGroupName:(nullable NSString *)identifier {
    NSString *oldName = @"";
    if (identifier) {
        for (WatchlistGroup *group in self.watchlistStore.groups) {
            if ([group.identifier isEqualToString:identifier]) {
                oldName = group.name;
                break;
            }
        }
        if (oldName.length == 0) {
            return;
        }
    }
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = identifier ? @"重命名分组" : @"新建分组";
    alert.informativeText = @"名称最多 10 个字，选项卡最多显示前 4 个字。悬停可查看完整名称。";
    [alert addButtonWithTitle:identifier ? @"保存" : @"创建"];
    [alert addButtonWithTitle:@"取消"];
    NSTextField *input = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300.0, 24.0)];
    input.placeholderString = @"例如：科技、医药、场内基金";
    input.stringValue = oldName;
    alert.accessoryView = input;
    alert.window.initialFirstResponder = input;

    while ([alert runModal] == NSAlertFirstButtonReturn) {
        NSError *error = nil;
        BOOL saved = identifier
            ? [self.watchlistStore renameGroup:identifier name:input.stringValue error:&error]
            : [self.watchlistStore createGroupWithName:input.stringValue error:&error] != nil;
        if (saved) {
            [self refreshAfterGroupChange];
            [self showMenuAfterReopen];
            return;
        }
        [self showErrorWithTitle:@"无法保存分组"
                         message:error.localizedDescription.length > 0
            ? error.localizedDescription : @"该分组已经不存在或不允许修改。"];
        if (!error) {
            return;
        }
    }
}

- (void)deleteSelectedGroup:(NSMenuItem *)item {
    NSString *identifier = item.representedObject;
    [self.statusMenu cancelTracking];
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *name = nil;
        for (WatchlistGroup *group in self.watchlistStore.groups) {
            if ([group.identifier isEqualToString:identifier]) {
                name = group.name;
            }
        }
        if (!name || [identifier isEqualToString:WatchlistDefaultGroupIdentifier]) {
            return;
        }
        [NSApp activateIgnoringOtherApps:YES];
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = [NSString stringWithFormat:@"删除分组“%@”？", name];
        alert.informativeText = @"将删除该分组及其中的自选记录，其他分组不受影响。";
        [alert addButtonWithTitle:@"删除分组"];
        [alert addButtonWithTitle:@"取消"];
        if ([alert runModal] == NSAlertFirstButtonReturn
            && [self.watchlistStore removeGroup:identifier]) {
            [self refreshAfterGroupChange];
            [self showMenuAfterReopen];
        }
    });
}

- (void)toggleLoginItem:(id)sender {
    (void)sender;
    [self.loginItemController refreshStatus];
    BOOL shouldEnable = !self.loginItemController.isEnabled;
    NSError *error = nil;
    if (![self.loginItemController setEnabled:shouldEnable error:&error]) {
        [self showErrorWithTitle:@"无法修改开机启动"
                         message:error.localizedDescription.length > 0
            ? error.localizedDescription
            : @"系统没有接受登录项设置。"];
        [self updateMenuState];
        return;
    }
    if (self.loginItemController.requiresApproval) {
        [NSApp activateIgnoringOtherApps:YES];
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"需要批准开机启动";
        alert.informativeText = @"请在系统设置的登录项中允许 StockBar。";
        [alert addButtonWithTitle:@"打开系统设置"];
        [alert addButtonWithTitle:@"稍后"];
        if ([alert runModal] == NSAlertFirstButtonReturn) {
            [self.loginItemController openSystemSettings];
        }
    }
    [self updateMenuState];
}

- (void)toggleTouchBar:(id)sender {
    (void)sender;
    if (self.touchBarController.wantsPersistentPresentation) {
        [self.touchBarController dismiss];
    } else {
        [self.touchBarController present];
    }
    [self updateMenuState];
}

- (void)toggleTrayVisibility:(id)sender {
    (void)sender;
    self.touchBarController.trayItemVisible = !self.touchBarController.trayItemVisible;
    [self updateMenuState];
}

- (void)quit:(id)sender {
    (void)sender;
    [NSApp terminate:nil];
}

- (void)showErrorWithTitle:(NSString *)title message:(NSString *)message {
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = title;
    alert.informativeText = message;
    [alert addButtonWithTitle:@"好"];
    [alert runModal];
}

@end
