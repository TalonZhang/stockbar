#import "StockSearchWindowController.h"
#import "WatchlistStore.h"

@interface StockSearchPanel : NSPanel
@end
@implementation StockSearchPanel
- (BOOL)canBecomeKeyWindow { return YES; }
@end

@interface SearchPanelContentView : NSView
@end
@implementation SearchPanelContentView
- (void)drawRect:(NSRect)rect {
    [NSColor.windowBackgroundColor setFill];
    NSRectFill(rect);
}
@end

@interface StockSearchWindowController () <NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate>
@property (nonatomic, strong) NSSearchField *searchField;
@property (nonatomic, strong) NSTextField *groupLabel;
@property (nonatomic, strong) NSTextField *statusLabel;
@property (nonatomic, strong) NSTableView *tableView;
@property (nonatomic, strong) NSButton *addButton;
@property (nonatomic, strong) NSScrollView *resultsScrollView;
@property (nonatomic, strong) NSTextField *hintLabel;
@property (nonatomic, strong) StockSearchService *searchService;
@property (nonatomic, copy) NSArray<StockSearchResult *> *results;
@property (nonatomic, copy) NSString *groupIdentifier;
@property (nonatomic, strong, nullable) NSTimer *searchTimer;
@property (nonatomic) NSUInteger queryRevision;
@property (nonatomic) BOOL adding;
@property (nonatomic) BOOL submitWhenReady;
@end

@implementation StockSearchWindowController

- (instancetype)init {
    NSPanel *panel = [[StockSearchPanel alloc] initWithContentRect:NSMakeRect(0, 0, 372.0, 360.0)
                                               styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskUtilityWindow)
                                                 backing:NSBackingStoreBuffered defer:NO];
    self = [super initWithWindow:panel];
    if (self) {
        panel.title = @"搜索自选";
        panel.floatingPanel = YES;
        panel.hidesOnDeactivate = YES;
        panel.becomesKeyOnlyIfNeeded = NO;
        panel.releasedWhenClosed = NO;
        panel.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace | NSWindowCollectionBehaviorFullScreenAuxiliary;
        panel.delegate = self;
        panel.contentView = [[SearchPanelContentView alloc] initWithFrame:NSMakeRect(0, 0, 372.0, 360.0)];
        _results = @[];
        _searchService = [[StockSearchService alloc] init];
        [self buildContent];
    }
    return self;
}

- (NSTextField *)labelWithFrame:(NSRect)frame size:(CGFloat)size {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.editable = NO;
    label.selectable = NO;
    label.font = [NSFont systemFontOfSize:size];
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    return label;
}

- (void)buildContent {
    NSView *content = self.window.contentView;
    self.groupLabel = [self labelWithFrame:NSMakeRect(16.0, 326.0, 340.0, 18.0) size:11.0];
    self.groupLabel.textColor = NSColor.secondaryLabelColor;
    [content addSubview:self.groupLabel];

    self.searchField = [[NSSearchField alloc] initWithFrame:NSMakeRect(16.0, 287.0, 340.0, 28.0)];
    self.searchField.placeholderString = @"代码、中文名称或拼音缩写，如 zjxc";
    self.searchField.font = [NSFont systemFontOfSize:13.0];
    self.searchField.delegate = self;
    self.searchField.target = self;
    self.searchField.action = @selector(submitSelection:);
    self.searchField.sendsWholeSearchString = YES;
    [content addSubview:self.searchField];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(16.0, 63.0, 340.0, 212.0)];
    self.resultsScrollView = scroll;
    scroll.borderType = NSBezelBorder;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    self.tableView = [[NSTableView alloc] initWithFrame:scroll.bounds];
    self.tableView.headerView = nil;
    self.tableView.rowHeight = 26.0;
    self.tableView.intercellSpacing = NSMakeSize(0, 0);
    self.tableView.allowsMultipleSelection = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.target = self;
    self.tableView.doubleAction = @selector(submitSelection:);
    NSTableColumn *name = [[NSTableColumn alloc] initWithIdentifier:@"name"];
    name.width = 218.0;
    [self.tableView addTableColumn:name];
    NSTableColumn *code = [[NSTableColumn alloc] initWithIdentifier:@"code"];
    code.width = 112.0;
    [self.tableView addTableColumn:code];
    scroll.documentView = self.tableView;
    [content addSubview:scroll];

    self.statusLabel = [self labelWithFrame:NSMakeRect(16.0, 40.0, 340.0, 18.0) size:11.0];
    self.statusLabel.textColor = NSColor.secondaryLabelColor;
    [content addSubview:self.statusLabel];
    NSTextField *hint = [self labelWithFrame:NSMakeRect(16.0, 13.0, 250.0, 18.0) size:11.0];
    self.hintLabel = hint;
    hint.stringValue = @"↑↓ 选择 · 回车添加 · Esc 取消";
    hint.textColor = NSColor.secondaryLabelColor;
    [content addSubview:hint];
    self.addButton = [NSButton buttonWithTitle:@"添加" target:self action:@selector(submitSelection:)];
    self.addButton.bezelStyle = NSBezelStyleRounded;
    self.addButton.keyEquivalent = @"\r";
    self.addButton.frame = NSMakeRect(276.0, 8.0, 80.0, 28.0);
    self.addButton.enabled = NO;
    [content addSubview:self.addButton];
    self.window.initialFirstResponder = self.searchField;
}

- (void)showQuery:(NSString *)query groupIdentifier:(NSString *)groupIdentifier groupName:(NSString *)groupName anchorRect:(NSRect)anchor {
    [self showQuery:query groupIdentifier:groupIdentifier groupName:groupName anchorRect:anchor submitImmediately:NO];
}

- (void)showQuery:(NSString *)query groupIdentifier:(NSString *)groupIdentifier groupName:(NSString *)groupName anchorRect:(NSRect)anchor submitImmediately:(BOOL)submit {
    [self stopSearch];
    self.submitWhenReady = submit;
    self.groupIdentifier = groupIdentifier;
    self.groupLabel.stringValue = [NSString stringWithFormat:@"添加到“%@” · A 股 / 场内基金", groupName];
    self.searchField.stringValue = query;
    [self setAdding:NO];
    self.results = @[];
    [self.tableView reloadData];
    self.window.title = @"添加自选";
    NSRect frame = self.window.frame;
    NSScreen *screen = nil;
    for (NSScreen *candidate in NSScreen.screens) {
        if (NSIntersectsRect(candidate.frame, anchor)) {
            screen = candidate;
            break;
        }
    }
    if (!screen) {
        screen = NSScreen.mainScreen;
    }
    if (screen) {
        NSRect visible = screen.visibleFrame;
        CGFloat x = NSIsEmptyRect(anchor) ? NSMaxX(visible) - NSWidth(frame) - 12.0 : NSMaxX(anchor) - NSWidth(frame);
        CGFloat top = NSIsEmptyRect(anchor) ? NSMaxY(visible) - 12.0 : NSMinY(anchor) - 4.0;
        CGFloat minX = NSMinX(visible) + 8.0;
        CGFloat maxX = NSMaxX(visible) - NSWidth(frame) - 8.0;
        x = x < minX ? minX : (x > maxX ? maxX : x);
        CGFloat y = top - NSHeight(frame);
        CGFloat minY = NSMinY(visible) + 8.0;
        CGFloat maxY = NSMaxY(visible) - NSHeight(frame) - 8.0;
        y = y < minY ? minY : (y > maxY ? maxY : y);
        [self.window setFrameOrigin:NSMakePoint(x, y)];
    }
    [NSApp activateIgnoringOtherApps:YES];
    [self showWindow:nil];
    [self.window makeKeyAndOrderFront:nil];
    [self.window makeFirstResponder:self.searchField];
    NSText *editor = self.searchField.currentEditor;
    editor.selectedRange = NSMakeRange(query.length, 0);
    [self performSearch];
}

- (void)stopSearch {
    self.queryRevision++;
    [self.searchTimer invalidate];
    self.searchTimer = nil;
    [self.searchService cancel];
}

- (void)windowWillClose:(NSNotification *)notification {
    (void)notification;
    [self stopSearch];
    self.submitWhenReady = NO;
}

- (void)controlTextDidChange:(NSNotification *)notification {
    (void)notification;
    if (self.adding) {
        return;
    }
    [self stopSearch];
    self.submitWhenReady = NO;
    self.results = @[];
    [self.tableView reloadData];
    self.addButton.enabled = NO;
    NSText *editor = self.searchField.currentEditor;
    if ([editor isKindOfClass:NSTextView.class] && [(NSTextView *)editor hasMarkedText]) {
        self.statusLabel.stringValue = @"输入完成后显示候选";
        return;
    }
    self.statusLabel.stringValue = self.searchField.stringValue.length > 0 ? @"正在搜索…" : @"输入名称、拼音缩写或代码开始搜索";
    [self updateAddButton];
    self.searchTimer = [NSTimer timerWithTimeInterval:0.3 target:self selector:@selector(searchTimerFired:) userInfo:nil repeats:NO];
    [[NSRunLoop mainRunLoop] addTimer:self.searchTimer forMode:NSRunLoopCommonModes];
}

- (void)searchTimerFired:(NSTimer *)timer {
    (void)timer;
    [self performSearch];
}

- (void)performSearch {
    [self.searchTimer invalidate];
    self.searchTimer = nil;
    NSString *query = [self.searchField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSUInteger revision = ++self.queryRevision;
    self.results = @[];
    [self.tableView reloadData];
    [self updateAddButton];
    self.statusLabel.toolTip = nil;
    if (query.length == 0 || query.length > 64) {
        [self.searchService cancel];
        self.submitWhenReady = NO;
        self.statusLabel.stringValue = query.length == 0 ? @"输入名称、拼音缩写或代码开始搜索" : @"关键词过长，请缩短后重试";
        return;
    }
    NSString *code = [WatchlistStore normalizedCodeFromInput:query];
    if (code && self.submitWhenReady) {
        [self.searchService cancel];
        self.submitWhenReady = NO;
        [self submitResult:[[StockSearchResult alloc] initWithCode:code name:code]];
        return;
    }
    self.statusLabel.stringValue = @"正在搜索…";
    __weak StockSearchWindowController *weakSelf = self;
    [self.searchService searchQuery:query completion:^(NSArray<StockSearchResult *> *results, NSError *error) {
        StockSearchWindowController *strongSelf = weakSelf;
        if (!strongSelf || strongSelf.queryRevision != revision || strongSelf.adding) {
            return;
        }
        strongSelf.results = results;
        [strongSelf.tableView reloadData];
        if (error) {
            strongSelf.submitWhenReady = NO;
            strongSelf.statusLabel.stringValue = @"搜索失败，请按回车重试或使用六位代码添加";
            strongSelf.statusLabel.toolTip = error.localizedDescription;
        } else if (results.count == 0) {
            strongSelf.submitWhenReady = NO;
            strongSelf.statusLabel.stringValue = @"未找到匹配的 A 股或场内基金，试试其他关键词";
        } else {
            strongSelf.statusLabel.stringValue = results.count == 1
                ? [NSString stringWithFormat:@"%@ · %@ · 回车添加", results[0].name, results[0].code]
                : [NSString stringWithFormat:@"找到 %lu 条候选，请选择后添加", (unsigned long)results.count];
            [strongSelf.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
            if (strongSelf.submitWhenReady) {
                strongSelf.submitWhenReady = NO;
                if (results.count == 1) {
                    [strongSelf submitResult:results[0]];
                }
            }
        }
        [strongSelf updateAddButton];
    }];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    (void)tableView;
    return (NSInteger)self.results.count;
}

- (nullable NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(nullable NSTableColumn *)column row:(NSInteger)row {
    if (row < 0 || (NSUInteger)row >= self.results.count) {
        return nil;
    }
    NSTableCellView *cell = [tableView makeViewWithIdentifier:column.identifier owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, column.width, 26.0)];
        cell.identifier = column.identifier;
        cell.textField = [self labelWithFrame:NSMakeRect(7.0, 3.0, column.width - 14.0, 20.0) size:12.0];
        cell.textField.autoresizingMask = NSViewWidthSizable;
        [cell addSubview:cell.textField];
    }
    StockSearchResult *result = self.results[(NSUInteger)row];
    BOOL nameColumn = [column.identifier isEqualToString:@"name"];
    cell.textField.stringValue = nameColumn ? result.name : [NSString stringWithFormat:@"%@ %@", result.marketLabel, result.code];
    cell.textField.alignment = nameColumn ? NSTextAlignmentLeft : NSTextAlignmentRight;
    cell.toolTip = [NSString stringWithFormat:@"%@ · %@ %@", result.name, result.marketLabel, result.code];
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    (void)notification;
    [self updateAddButton];
}

- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row {
    (void)tableView;
    (void)row;
    return !self.adding;
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command {
    (void)control;
    if (textView.hasMarkedText) {
        return NO;
    }
    if (command == @selector(moveDown:) || command == @selector(moveUp:)) {
        NSInteger count = (NSInteger)self.results.count;
        if (count > 1 && !self.adding) {
            NSInteger row = self.tableView.selectedRow;
            row += command == @selector(moveDown:) ? 1 : -1;
            row = row < 0 ? 0 : (row >= count ? count - 1 : row);
            [self.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
            [self.tableView scrollRowToVisible:row];
        }
        return YES;
    }
    if (command == @selector(insertNewline:)) {
        [self submitSelection:nil];
        return YES;
    }
    if (command == @selector(cancelOperation:)) {
        [self close];
        return YES;
    }
    return NO;
}

- (void)cancelOperation:(id)sender {
    (void)sender;
    [self close];
}

- (void)setAdding:(BOOL)adding {
    _adding = adding;
    self.searchField.enabled = !adding;
    [self updateAddButton];
}

- (void)updateAddButton {
    NSString *query = [self.searchField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    self.addButton.enabled = !self.adding && query.length > 0;
    self.addButton.title = self.results.count > 0 || [WatchlistStore normalizedCodeFromInput:query]
        ? @"添加" : @"搜索";
}

- (void)submitSelection:(id)sender {
    (void)sender;
    if (self.adding) {
        return;
    }
    NSText *editor = self.searchField.currentEditor;
    if ([editor isKindOfClass:NSTextView.class] && [(NSTextView *)editor hasMarkedText]) {
        return;
    }
    NSString *query = [self.searchField.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *code = [WatchlistStore normalizedCodeFromInput:query];
    if (code) {
        [self submitResult:[[StockSearchResult alloc] initWithCode:code name:code]];
        return;
    }
    if (self.results.count == 1) {
        [self submitResult:self.results[0]];
        return;
    }
    NSInteger row = self.tableView.selectedRow;
    if (row < 0 || (NSUInteger)row >= self.results.count) {
        self.submitWhenReady = YES;
        [self performSearch];
        return;
    }
    [self submitResult:self.results[(NSUInteger)row]];
}

- (void)submitResult:(StockSearchResult *)result {
    if (self.adding) { return; }
    [self setAdding:YES];
    self.statusLabel.stringValue = @"正在验证并添加…";
    NSUInteger revision = self.queryRevision;
    __weak StockSearchWindowController *weakSelf = self;
    [self.delegate stockSearchController:self didChooseResult:result
                        groupIdentifier:self.groupIdentifier completion:^(NSError *error) {
        StockSearchWindowController *strongSelf = weakSelf;
        if (!strongSelf || revision != strongSelf.queryRevision) {
            return;
        }
        [strongSelf setAdding:NO];
        if (error) {
            strongSelf.statusLabel.stringValue = error.localizedDescription;
            strongSelf.statusLabel.toolTip = error.localizedDescription;
            [strongSelf.window makeFirstResponder:strongSelf.searchField];
        } else {
            [strongSelf close];
        }
    }];
}

@end
