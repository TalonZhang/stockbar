#import <AppKit/AppKit.h>
#import "StockSearchWindowController.h"
#import "AddStockMenuItemView.h"

@interface StockSearchWindowController (Testing)
- (void)performSearch;
- (void)controlTextDidChange:(nullable NSNotification *)notification;
- (BOOL)control:(NSControl *)control textView:(NSTextView *)view doCommandBySelector:(SEL)command;
@end

@interface EntryTestDelegate : NSObject <AddStockMenuItemViewDelegate>
@property (nonatomic) NSUInteger editingRequests;
@end
@implementation EntryTestDelegate
- (void)addStockMenuItemViewDidRequestEditing:(AddStockMenuItemView *)view { (void)view; self.editingRequests++; }
- (void)addStockMenuItemView:(AddStockMenuItemView *)view didSubmitInput:(NSString *)input { (void)view; (void)input; }
@end

@interface FakePanelSearch : StockSearchService
@property (nonatomic, strong) NSMutableArray<StockSearchCompletion> *callbacks;
@end
@implementation FakePanelSearch
- (instancetype)init { self = [super init]; if (self) { _callbacks = [NSMutableArray array]; } return self; }
- (void)cancel {}
- (void)searchQuery:(NSString *)query completion:(StockSearchCompletion)completion {
    (void)query;
    [self.callbacks addObject:[completion copy]];
}
@end

@interface PanelDelegate : NSObject <StockSearchWindowControllerDelegate>
@property (nonatomic) NSUInteger addRequests;
@property (nonatomic, strong) StockSearchResult *lastResult;
@property (nonatomic, copy) NSString *lastGroup;
@property (nonatomic, copy) SearchAddCompletion completion;
@end
@implementation PanelDelegate
- (void)stockSearchController:(StockSearchWindowController *)controller didChooseResult:(StockSearchResult *)result
             groupIdentifier:(NSString *)groupIdentifier completion:(SearchAddCompletion)completion {
    (void)controller;
    self.addRequests++;
    self.lastResult = result;
    self.lastGroup = groupIdentifier;
    self.completion = completion;
}
@end

static void Check(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr, "%s\n", message.UTF8String); exit(1); }
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [NSApp finishLaunching];
        AddStockMenuItemView *entry = [[AddStockMenuItemView alloc] initWithFrame:NSZeroRect];
        EntryTestDelegate *entryDelegate = [[EntryTestDelegate alloc] init];
        entry.delegate = entryDelegate;
        NSButton *entryButton = [entry valueForKey:@"entryButton"];
        [entryButton performClick:nil];
        Check(entryDelegate.editingRequests == 1 && entry.subviews.count == 1
              && [entryButton.title isEqualToString:@"＋ 添加自选"],
              @"Add button did not replace the old inline input and open the input panel");
        StockSearchWindowController *controller = [[StockSearchWindowController alloc] init];
        FakePanelSearch *service = [[FakePanelSearch alloc] init];
        PanelDelegate *delegate = [[PanelDelegate alloc] init];
        controller.delegate = delegate;
        [controller setValue:service forKey:@"searchService"];
        [controller showQuery:@"红利低波" groupIdentifier:@"group-A" groupName:@"场内基金" anchorRect:NSZeroRect];
        NSSearchField *field = [controller valueForKey:@"searchField"];
        NSTableView *table = [controller valueForKey:@"tableView"];
        NSTextField *status = [controller valueForKey:@"statusLabel"];
        Check(controller.window.isVisible && field.currentEditor != nil, @"Search panel did not establish a native text editor");
        Check(field.sendsWholeSearchString, @"Search field could submit while typing");
        NSArray *results = @[
            [[StockSearchResult alloc] initWithCode:@"512890" name:@"红利低波ETF华泰柏瑞"],
            [[StockSearchResult alloc] initWithCode:@"563020" name:@"红利低波ETF易方达"]
        ];
        service.callbacks.lastObject(results, nil);
        Check(table.numberOfRows == 2 && delegate.addRequests == 0, @"Candidates missing or added without selection");
        NSTextView *editor = (NSTextView *)field.currentEditor;
        NSScrollView *scroll = [controller valueForKey:@"resultsScrollView"];
        Check(!scroll.isHidden && delegate.addRequests == 0, @"Live candidates were hidden until Return or added without confirmation");
        Check(scroll.contentSize.height >= table.rowHeight * StockSearchResultLimit, @"Eight candidate rows do not fit in the list");
        [controller control:field textView:editor doCommandBySelector:@selector(moveDown:)];
        Check(table.selectedRow == 1, @"Arrow selection failed");
        if (argc > 1) {
            NSString *path = [NSString stringWithUTF8String:argv[1]];
            for (NSString *name in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
                controller.window.appearance = [NSAppearance appearanceNamed:name];
                [controller.window.contentView layoutSubtreeIfNeeded];
                [controller.window displayIfNeeded];
                NSView *view = controller.window.contentView;
                NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
                [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
                NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
                NSString *output = [name isEqualToString:NSAppearanceNameAqua] ? path
                    : [[path stringByDeletingPathExtension] stringByAppendingString:@"-dark.png"];
                Check([png writeToFile:output atomically:YES], @"Search preview failed");
            }
        }
        [controller control:field textView:editor doCommandBySelector:@selector(insertNewline:)];
        Check(delegate.addRequests == 1 && [delegate.lastResult.code isEqualToString:@"563020"]
              && [delegate.lastGroup isEqualToString:@"group-A"], @"Wrong candidate/group submitted");
        [controller control:field textView:editor doCommandBySelector:@selector(insertNewline:)];
        Check(delegate.addRequests == 1, @"Repeated Return added duplicate requests");
        delegate.completion([NSError errorWithDomain:@"test" code:1 userInfo:@{NSLocalizedDescriptionKey: @"已在该分组中"}]);
        Check(controller.window.isVisible && field.isEnabled && [status.stringValue isEqualToString:@"已在该分组中"], @"Validation failure closed panel or blocked editing");
        [controller control:field textView:editor doCommandBySelector:@selector(insertNewline:)];
        delegate.completion(nil);
        Check(!controller.window.isVisible, @"Successful add did not close search");

        NSUInteger countBeforeUnique = delegate.addRequests;
        StockSearchResult *unique = [[StockSearchResult alloc] initWithCode:@"300308" name:@"中际旭创"];
        [controller showQuery:@"zjxc" groupIdentifier:@"group-B" groupName:@"科技" anchorRect:NSZeroRect];
        service.callbacks.lastObject(@[unique], nil);
        Check(delegate.addRequests == countBeforeUnique && !scroll.isHidden, @"Live unique match hidden or added before Return");
        if (argc > 1) {
            controller.window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
            [controller.window.contentView layoutSubtreeIfNeeded];
            NSView *view = controller.window.contentView;
            NSBitmapImageRep *bitmap = [view bitmapImageRepForCachingDisplayInRect:view.bounds];
            [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
            NSData *png = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
            NSString *path = [[[NSString stringWithUTF8String:argv[1]] stringByDeletingPathExtension] stringByAppendingString:@"-single.png"];
            Check([png writeToFile:path atomically:YES], @"Compact preview failed");
        }
        [controller control:field textView:(NSTextView *)field.currentEditor doCommandBySelector:@selector(insertNewline:)];
        Check(delegate.addRequests == countBeforeUnique + 1, @"Cached unique match required a second confirmation");
        delegate.completion(nil);
        countBeforeUnique = delegate.addRequests;
        [controller showQuery:@"zjxc" groupIdentifier:@"group-B" groupName:@"科技" anchorRect:NSZeroRect submitImmediately:YES];
        service.callbacks.lastObject(@[unique], nil);
        Check(delegate.addRequests == countBeforeUnique + 1
              && [delegate.lastResult.code isEqualToString:@"300308"], @"Unique result did not add directly without candidates");
        delegate.completion(nil);

        NSUInteger countBeforeIME = delegate.addRequests;
        [controller showQuery:@"" groupIdentifier:@"group-B" groupName:@"科技" anchorRect:NSZeroRect];
        editor = (NSTextView *)field.currentEditor;
        Check(controller.window.canBecomeKeyWindow && editor != nil, @"Input panel cannot receive IME editing");
        NSUInteger requestsBeforeIME = service.callbacks.count;
        [editor setMarkedText:@"zhongjixuchuang" selectedRange:NSMakeRange(14, 0) replacementRange:NSMakeRange(NSNotFound, 0)];
        [controller controlTextDidChange:nil];
        Check(editor.hasMarkedText, @"Native field editor did not retain marked text");
        Check(![controller control:field textView:editor doCommandBySelector:@selector(insertNewline:)],
              @"IME commit Return was intercepted as an add command");
        Check(service.callbacks.count == requestsBeforeIME && delegate.addRequests == countBeforeIME,
              @"Search/add started before Chinese composition committed");
        [editor insertText:@"中际旭创" replacementRange:NSMakeRange(NSNotFound, 0)];
        Check(!editor.hasMarkedText && [field.stringValue isEqualToString:@"中际旭创"], @"Chinese text did not commit to the input field");
        [controller controlTextDidChange:nil];
        [controller control:field textView:editor doCommandBySelector:@selector(insertNewline:)];
        service.callbacks.lastObject(@[unique], nil);
        Check(delegate.addRequests == countBeforeIME + 1,
              @"Committed Chinese unique result did not add directly");
        delegate.completion(nil);

        [controller showQuery:@"512890" groupIdentifier:@"group-A" groupName:@"场内基金" anchorRect:NSZeroRect];
        NSUInteger requestsBeforeCode = service.callbacks.count;
        [controller control:field textView:(NSTextView *)field.currentEditor doCommandBySelector:@selector(insertNewline:)];
        Check([delegate.lastResult.code isEqualToString:@"512890"] && service.callbacks.count == requestsBeforeCode,
              @"Six-digit code unnecessarily opened candidates or called search");
        delegate.completion(nil);

        [controller showQuery:@"zjxc" groupIdentifier:@"group-B" groupName:@"科技" anchorRect:NSZeroRect];
        StockSearchCompletion old = service.callbacks.lastObject;
        field.stringValue = @"白酒";
        [controller controlTextDidChange:nil];
        NSUInteger pendingCount = service.callbacks.count;
        NSDate *liveSearchDeadline = [NSDate dateWithTimeIntervalSinceNow:1.0];
        while (service.callbacks.count == pendingCount && liveSearchDeadline.timeIntervalSinceNow > 0.0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        Check(service.callbacks.count > pendingCount, @"Typing did not trigger a search without Return");
        StockSearchCompletion latest = service.callbacks.lastObject;
        old(results, nil);
        Check(table.numberOfRows == 0, @"Outdated results reappeared after editing");
        latest(@[[[StockSearchResult alloc] initWithCode:@"161725" name:@"白酒基金LOF"]], nil);
        Check(table.numberOfRows == 1 && !scroll.isHidden, @"Live search results were not displayed immediately");
        [controller control:field textView:(NSTextView *)field.currentEditor doCommandBySelector:@selector(cancelOperation:)];
        Check(!controller.window.isVisible, @"Escape did not dismiss search");
        latest(results, nil);
        Check(!controller.window.isVisible && table.numberOfRows == 1, @"Closed search accepted delayed results");
        puts("Search panel: entry handoff, Chinese composition, unique direct add, multiple selection, code add and cancellation passed");
    }
    return 0;
}
