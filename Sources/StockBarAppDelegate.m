#import "StockBarAppDelegate.h"

#import "AddStockMenuItemView.h"
#import "LoginItemController.h"
#import "PersistentTouchBarController.h"
#import "StockMenuItemView.h"
#import "StockQuote.h"
#import "TencentQuoteService.h"
#import "TouchBarHardware.h"
#import "WatchlistStore.h"

static NSString * const LegacyBundleIdentifier = @"dev.touchbarstocks.prototype";
static NSString * const LegacyMigrationKey = @"migration.touchbarstocks.v1";
static NSString * const WatchlistDefaultsKey = @"watchlist.codes.v1";
static NSString * const QuoteSourceDefaultsKey = @"quote.source.v1";

@interface StockBarAppDelegate () <StockMenuItemViewDelegate, AddStockMenuItemViewDelegate>

@property (nonatomic, strong) NSStatusItem *statusItem;
@property (nonatomic, strong) NSMenu *statusMenu;
@property (nonatomic, strong) NSMenuItem *quoteStatusMenuItem;
@property (nonatomic, strong) NSMutableArray<NSMenuItem *> *stockMenuItems;
@property (nonatomic, strong) AddStockMenuItemView *addStockView;
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
@property (nonatomic, strong, nullable) NSTimer *watchdogTimer;
@property (nonatomic) BOOL touchBarFeatureAvailable;
@property (nonatomic, copy, nullable) NSString *draggedStockCode;
@property (nonatomic) NSInteger proposedDropIndex;

@end

@implementation StockBarAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];

    [self migrateLegacyPreferencesIfNeeded];
    self.watchlistStore = [[WatchlistStore alloc] init];
    self.quoteService = [[TencentQuoteService alloc] initWithCodes:[self quoteCodes]];
    self.loginItemController = [[LoginItemController alloc] init];
    self.latestQuotes = [self placeholderQuotesForCodes:[self quoteCodes]];
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
        strongSelf.latestQuotes = quotes;
        strongSelf.quoteStatusMenuItem.title = statusText;
        [strongSelf.touchBarController updateQuotes:quotes];
        [strongSelf updateStatusTooltip];
        [strongSelf updateStockRows];
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
    [codes addObjectsFromArray:self.watchlistStore.codes];
    return codes;
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
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
    self.statusItem.button.toolTip = @"StockBar · A股行情";
    if (@available(macOS 11.0, *)) {
        NSImage *image = [NSImage imageWithSystemSymbolName:@"chart.line.uptrend.xyaxis"
                                   accessibilityDescription:@"StockBar"];
        image.template = YES;
        self.statusItem.button.image = image;
        self.statusItem.button.imagePosition = NSImageOnly;
    } else {
        self.statusItem.button.title = @"股";
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

    self.quoteStatusMenuItem = [[NSMenuItem alloc] initWithTitle:@"正在获取行情…" action:nil keyEquivalent:@""];
    self.quoteStatusMenuItem.enabled = NO;
    [menu addItem:self.quoteStatusMenuItem];

    [self rebuildStockRows];
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
    [self.touchBarController restoreIfNeeded];
    [self updateMenuState];
}

- (void)updateStatusTooltip {
    if (self.latestQuotes.count == 0) {
        self.statusItem.button.toolTip = @"StockBar · 暂无行情";
        return;
    }
    StockQuote *quote = self.latestQuotes.firstObject;
    self.statusItem.button.toolTip = quote.isAvailable
        ? [NSString stringWithFormat:@"%@  %+.2f%%  ¥%.2f", quote.name, quote.percentChange, quote.price]
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
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.watchlistStore removeCode:code]) {
            [self.quoteService setCodes:[self quoteCodes]];
            [self.quoteService refresh];
            [self updateMenuState];
        }
    });
}

- (void)stockMenuItemViewDidBeginDragging:(StockMenuItemView *)view {
    self.draggedStockCode = view.stockCode;
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
    NSInteger targetIndex = self.proposedDropIndex;
    self.draggedStockCode = nil;
    self.proposedDropIndex = NSNotFound;
    if (code.length == 0 || targetIndex == NSNotFound || targetIndex < 0) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if ([self.watchlistStore moveCode:code toIndex:(NSUInteger)targetIndex]) {
            [self.quoteService setCodes:[self quoteCodes]];
            [self.quoteService refresh];
            [self updateMenuState];
        }
    });
}

- (void)refreshQuotes:(id)sender {
    (void)sender;
    self.quoteStatusMenuItem.title = @"正在刷新行情…";
    [self.quoteService refresh];
}

- (void)addStockMenuItemView:(AddStockMenuItemView *)view didSubmitInput:(NSString *)input {
    NSString *code = [WatchlistStore normalizedCodeFromInput:input];
    if (!code) {
        [self showErrorWithTitle:@"代码格式不正确" message:@"请输入有效的六位 A 股代码。"];
        [view focusAndSelectInput];
        return;
    }
    if ([self.watchlistStore containsCode:code]) {
        [self showErrorWithTitle:@"已经添加" message:[NSString stringWithFormat:@"%@ 已在自选股中。", code]];
        [view focusAndSelectInput];
        return;
    }

    [view setValidating:YES];
    self.quoteStatusMenuItem.title = [NSString stringWithFormat:@"正在验证 %@…", code];
    __weak StockBarAppDelegate *weakSelf = self;
    [self.quoteService validateCode:code completion:^(StockQuote *quote, NSError *error) {
        StockBarAppDelegate *strongSelf = weakSelf;
        if (!quote || error) {
            [view setValidating:NO];
            [strongSelf showErrorWithTitle:@"无法添加股票"
                                   message:error.localizedDescription.length > 0
                ? error.localizedDescription
                : @"行情源没有返回该股票。"];
            [view focusAndSelectInput];
            return;
        }
        if ([strongSelf.watchlistStore addCode:code]) {
            [view clearInput];
            [strongSelf.quoteService setCodes:[strongSelf quoteCodes]];
            [strongSelf.quoteService refresh];
            [strongSelf updateMenuState];
        } else {
            [view setValidating:NO];
        }
    }];
}

- (void)selectQuoteSource:(NSMenuItem *)menuItem {
    self.quoteService.source = (QuoteSource)menuItem.tag;
    self.quoteStatusMenuItem.title = [NSString stringWithFormat:@"正在切换到 %@…",
        [TencentQuoteService displayNameForSource:self.quoteService.source]];
    [self updateMenuState];
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
