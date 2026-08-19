#import "PersistentTouchBarController.h"

#import <dlfcn.h>
#import <math.h>
#import <objc/message.h>

#import "StockQuote.h"

static NSTouchBarItemIdentifier const StockSlotPrefix = @"dev.touchbarstocks.slot.";
static NSTouchBarItemIdentifier const NextPageIdentifier = @"dev.touchbarstocks.next";
static NSTouchBarItemIdentifier const EmptyItemIdentifier = @"dev.touchbarstocks.empty";
static NSTouchBarItemIdentifier const TrayItemIdentifier = @"dev.touchbarstocks.controlstrip";
static const NSUInteger VisibleStockSlotCount = 4;

typedef void (*DFRElementSetControlStripPresenceFn)(NSTouchBarItemIdentifier identifier, BOOL present);
typedef void (*DFRSystemModalShowsCloseBoxFn)(BOOL show);
typedef void (*SendOneObjectFn)(id receiver, SEL selector, id object);
typedef void (*PresentTouchBarFn)(id receiver, SEL selector, NSTouchBar *touchBar, long long placement, NSTouchBarItemIdentifier identifier);
typedef void (*PresentTouchBarSimpleFn)(id receiver, SEL selector, NSTouchBar *touchBar, NSTouchBarItemIdentifier identifier);

@interface PersistentTouchBarController ()

@property (nonatomic) BOOL available;
@property (nonatomic) BOOL presented;
@property (nonatomic, copy) NSString *diagnosticText;
@property (nonatomic, strong) NSTouchBar *touchBar;
@property (nonatomic, strong, nullable) NSCustomTouchBarItem *trayItem;
@property (nonatomic, copy) NSArray<StockQuote *> *quotes;
@property (nonatomic, strong) NSMutableDictionary<NSTouchBarItemIdentifier, NSButton *> *buttons;
@property (nonatomic) BOOL showsPrices;
@property (nonatomic) BOOL registeredTrayItem;
@property (nonatomic) NSUInteger pageOffset;

@property (nonatomic) void *privateFramework;
@property (nonatomic) DFRElementSetControlStripPresenceFn setControlStripPresence;
@property (nonatomic) DFRSystemModalShowsCloseBoxFn setCloseBoxVisibility;
@property (nonatomic) SEL presentSelector;
@property (nonatomic) SEL simplePresentSelector;
@property (nonatomic) SEL dismissSelector;
@property (nonatomic) SEL addTrayItemSelector;
@property (nonatomic) SEL removeTrayItemSelector;

@end

@implementation PersistentTouchBarController

- (instancetype)init {
    self = [super init];
    if (self) {
        _diagnosticText = @"尚未初始化";
        _buttons = [NSMutableDictionary dictionary];
        _quotes = @[];
        _trayItemVisible = YES;
        _wantsPersistentPresentation = YES;
        [self loadPrivateAPI];
        [self buildTouchBar];
    }
    return self;
}

- (void)dealloc {
    [self stop];
}

- (void)loadPrivateAPI {
    self.privateFramework = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_LAZY | RTLD_LOCAL);
    if (!self.privateFramework) {
        self.diagnosticText = @"无法加载 DFRFoundation";
        return;
    }

    self.setControlStripPresence = (DFRElementSetControlStripPresenceFn)dlsym(self.privateFramework, "DFRElementSetControlStripPresenceForIdentifier");
    self.setCloseBoxVisibility = (DFRSystemModalShowsCloseBoxFn)dlsym(self.privateFramework, "DFRSystemModalShowsCloseBoxWhenFrontMost");
    self.presentSelector = NSSelectorFromString(@"presentSystemModalTouchBar:placement:systemTrayItemIdentifier:");
    self.simplePresentSelector = NSSelectorFromString(@"presentSystemModalTouchBar:systemTrayItemIdentifier:");
    self.dismissSelector = NSSelectorFromString(@"dismissSystemModalTouchBar:");
    self.addTrayItemSelector = NSSelectorFromString(@"addSystemTrayItem:");
    self.removeTrayItemSelector = NSSelectorFromString(@"removeSystemTrayItem:");

    BOOL hasPresentSelector = [[NSTouchBar class] respondsToSelector:self.simplePresentSelector]
        || [[NSTouchBar class] respondsToSelector:self.presentSelector];
    BOOL hasSelectors = hasPresentSelector
        && [[NSTouchBar class] respondsToSelector:self.dismissSelector]
        && [[NSTouchBarItem class] respondsToSelector:self.addTrayItemSelector]
        && [[NSTouchBarItem class] respondsToSelector:self.removeTrayItemSelector];

    self.available = self.setControlStripPresence != NULL
        && self.setCloseBoxVisibility != NULL
        && hasSelectors;
    self.diagnosticText = self.available ? @"私有 Touch Bar 接口可用" : @"当前系统缺少常驻接口";
}

- (void)buildTouchBar {
    self.touchBar = [[NSTouchBar alloc] init];
    self.touchBar.delegate = self;
    self.touchBar.customizationIdentifier = @"dev.touchbarstocks.main";
    [self updateDefaultItemIdentifiers];
}

- (void)updateQuotes:(NSArray<StockQuote *> *)quotes {
    self.quotes = quotes;
    if (self.pageOffset >= quotes.count) {
        self.pageOffset = 0;
    }
    [self updateDefaultItemIdentifiers];
    [self configureVisibleStockButtons];
}

- (void)updateDefaultItemIdentifiers {
    NSMutableArray<NSTouchBarItemIdentifier> *identifiers = [NSMutableArray array];
    if (self.quotes.count == 0) {
        [identifiers addObject:EmptyItemIdentifier];
    } else {
        NSUInteger remaining = self.quotes.count - self.pageOffset;
        NSUInteger visibleCount = remaining < VisibleStockSlotCount ? remaining : VisibleStockSlotCount;
        for (NSUInteger slot = 0; slot < visibleCount; slot++) {
            [identifiers addObject:[StockSlotPrefix stringByAppendingFormat:@"%lu", (unsigned long)slot]];
        }
        if (self.quotes.count > VisibleStockSlotCount) {
            [identifiers addObject:NextPageIdentifier];
        }
    }

    if (![self.touchBar.defaultItemIdentifiers isEqualToArray:identifiers]) {
        self.touchBar.defaultItemIdentifiers = identifiers;
        self.touchBar.customizationAllowedItemIdentifiers = identifiers;
    }
}

- (void)configureVisibleStockButtons {
    for (NSUInteger slot = 0; slot < VisibleStockSlotCount; slot++) {
        NSString *identifier = [StockSlotPrefix stringByAppendingFormat:@"%lu", (unsigned long)slot];
        NSButton *button = self.buttons[identifier];
        NSUInteger quoteIndex = self.pageOffset + slot;
        if (button && quoteIndex < self.quotes.count) {
            [self configureButton:button withQuote:self.quotes[quoteIndex]];
        }
    }
}

- (BOOL)present {
    [self updateDefaultItemIdentifiers];
    return [self presentPreservingLayout];
}

- (BOOL)presentPreservingLayout {
    self.wantsPersistentPresentation = YES;
    if (!self.available) {
        return NO;
    }

    [self registerTrayItemIfNeeded];
    self.setCloseBoxVisibility(YES);

    if ([[NSTouchBar class] respondsToSelector:self.simplePresentSelector]) {
        PresentTouchBarSimpleFn presentFunction = (PresentTouchBarSimpleFn)objc_msgSend;
        presentFunction([NSTouchBar class], self.simplePresentSelector, self.touchBar, TrayItemIdentifier);
    } else {
        PresentTouchBarFn presentFunction = (PresentTouchBarFn)objc_msgSend;
        presentFunction([NSTouchBar class], self.presentSelector, self.touchBar, 0, TrayItemIdentifier);
    }
    self.setCloseBoxVisibility(YES);
    self.presented = YES;
    self.diagnosticText = @"Touch Bar 已显示";
    [self applyTrayItemVisibility];
    return YES;
}

- (void)dismiss {
    self.wantsPersistentPresentation = NO;
    [self dismissWithoutChangingPreference];
}

- (void)dismissWithoutChangingPreference {
    if (!self.available || !self.presented) {
        return;
    }

    SendOneObjectFn dismissFunction = (SendOneObjectFn)objc_msgSend;
    dismissFunction([NSTouchBar class], self.dismissSelector, self.touchBar);
    self.presented = NO;
    self.diagnosticText = @"Touch Bar 已关闭";
}

- (void)restoreIfNeeded {
    if (!self.available || !self.wantsPersistentPresentation) {
        return;
    }

    if (self.presented && !self.touchBar.isVisible) {
        self.presented = NO;
        self.wantsPersistentPresentation = NO;
        self.diagnosticText = @"Touch Bar 已关闭";
    }
}

- (void)stop {
    [self dismissWithoutChangingPreference];

    if (self.registeredTrayItem && self.available) {
        self.setControlStripPresence(TrayItemIdentifier, NO);
        SendOneObjectFn removeFunction = (SendOneObjectFn)objc_msgSend;
        removeFunction([NSTouchBarItem class], self.removeTrayItemSelector, self.trayItem);
        self.registeredTrayItem = NO;
        self.trayItem = nil;
    }

    if (self.privateFramework) {
        dlclose(self.privateFramework);
        self.privateFramework = NULL;
    }
}

- (void)setTrayItemVisible:(BOOL)trayItemVisible {
    _trayItemVisible = trayItemVisible;
    [self applyTrayItemVisibility];
}

- (void)registerTrayItemIfNeeded {
    if (self.registeredTrayItem) {
        return;
    }

    NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:TrayItemIdentifier];
    NSButton *button = [NSButton buttonWithTitle:@"股" target:self action:@selector(toggleFromTray:)];
    button.bordered = NO;
    button.toolTip = @"显示或隐藏股票栏";
    [button.widthAnchor constraintEqualToConstant:32.0].active = YES;
    item.view = button;
    item.customizationLabel = @"股票栏";
    self.trayItem = item;

    SendOneObjectFn addFunction = (SendOneObjectFn)objc_msgSend;
    addFunction([NSTouchBarItem class], self.addTrayItemSelector, item);
    self.registeredTrayItem = YES;
}

- (void)applyTrayItemVisibility {
    if (self.registeredTrayItem && self.setControlStripPresence) {
        self.setControlStripPresence(TrayItemIdentifier, self.trayItemVisible);
    }
}

- (void)toggleFromTray:(id)sender {
    (void)sender;
    if (self.presented && self.touchBar.isVisible) {
        [self dismiss];
    } else {
        [self present];
    }
}

- (nullable NSTouchBarItem *)touchBar:(NSTouchBar *)touchBar
                makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier {
    (void)touchBar;
    if ([identifier isEqualToString:EmptyItemIdentifier]) {
        NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
        NSButton *button = [NSButton buttonWithTitle:@"请从菜单栏添加自选股" target:nil action:nil];
        button.bordered = NO;
        button.enabled = NO;
        [button.widthAnchor constraintGreaterThanOrEqualToConstant:180.0].active = YES;
        item.view = button;
        item.customizationLabel = @"空自选股提示";
        return item;
    }

    if ([identifier isEqualToString:NextPageIdentifier]) {
        NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
        NSButton *button = [NSButton buttonWithTitle:@"›" target:self action:@selector(nextPage:)];
        button.bordered = NO;
        button.toolTip = @"下一组自选股";
        [button.widthAnchor constraintEqualToConstant:34.0].active = YES;
        item.view = button;
        item.visibilityPriority = 3000.0;
        item.customizationLabel = @"下一组自选股";
        return item;
    }

    if (![identifier hasPrefix:StockSlotPrefix]) {
        return nil;
    }

    NSInteger slot = [[identifier substringFromIndex:StockSlotPrefix.length] integerValue];
    NSCustomTouchBarItem *item = [[NSCustomTouchBarItem alloc] initWithIdentifier:identifier];
    NSButton *button = [NSButton buttonWithTitle:@"加载中…" target:self action:@selector(stockButtonPressed:)];
    button.tag = slot;
    button.bordered = NO;
    [button.widthAnchor constraintGreaterThanOrEqualToConstant:112.0].active = YES;
    [button.widthAnchor constraintLessThanOrEqualToConstant:150.0].active = YES;
    item.view = button;
    item.visibilityPriority = 1000.0 - (float)slot;
    item.customizationLabel = [NSString stringWithFormat:@"自选股位置 %ld", (long)slot + 1];
    self.buttons[identifier] = button;

    NSUInteger slotIndex = slot < 0 ? 0 : (NSUInteger)slot;
    NSUInteger quoteIndex = self.pageOffset + slotIndex;
    if (quoteIndex < self.quotes.count) {
        StockQuote *quote = self.quotes[quoteIndex];
        item.customizationLabel = quote.name;
        [self configureButton:button withQuote:quote];
    }
    return item;
}

- (void)stockButtonPressed:(NSButton *)button {
    (void)button;
    self.showsPrices = !self.showsPrices;
    [self configureVisibleStockButtons];
}

- (void)nextPage:(id)sender {
    (void)sender;
    self.pageOffset += VisibleStockSlotCount;
    if (self.pageOffset >= self.quotes.count) {
        self.pageOffset = 0;
    }
    [self updateDefaultItemIdentifiers];
    [self configureVisibleStockButtons];
}

- (void)configureButton:(NSButton *)button withQuote:(StockQuote *)quote {
    if (!quote.isAvailable) {
        NSString *title = [NSString stringWithFormat:@"%@ --", quote.name];
        button.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{
            NSForegroundColorAttributeName: NSColor.secondaryLabelColor,
            NSFontAttributeName: [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium]
        }];
        button.accessibilityTitle = [NSString stringWithFormat:@"%@，行情暂不可用", quote.code];
        return;
    }

    NSString *value = self.showsPrices
        ? [NSString stringWithFormat:@"¥%.2f", quote.price]
        : [NSString stringWithFormat:@"%+.2f%%", quote.percentChange];
    NSString *title = [NSString stringWithFormat:@"%@ %@", quote.name, value];

    NSColor *color;
    if (fabs(quote.percentChange) < 0.0001) {
        color = NSColor.secondaryLabelColor;
    } else {
        color = quote.percentChange > 0.0 ? NSColor.systemRedColor : NSColor.systemGreenColor;
    }

    NSFont *font;
    if (@available(macOS 10.15, *)) {
        font = [NSFont monospacedDigitSystemFontOfSize:13.0 weight:NSFontWeightMedium];
    } else {
        font = [NSFont systemFontOfSize:13.0 weight:NSFontWeightMedium];
    }

    button.attributedTitle = [[NSAttributedString alloc] initWithString:title attributes:@{
        NSForegroundColorAttributeName: color,
        NSFontAttributeName: font
    }];
    NSString *direction = quote.percentChange > 0.0 ? @"上涨" : (quote.percentChange < 0.0 ? @"下跌" : @"平盘");
    button.accessibilityTitle = [NSString stringWithFormat:@"%@，%@ %.2f%%，现价 %.2f", quote.name, direction, fabs(quote.percentChange), quote.price];
}

@end
