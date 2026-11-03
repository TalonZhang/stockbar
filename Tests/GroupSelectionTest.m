#import <AppKit/AppKit.h>
#import "AddStockMenuItemView.h"
#import "GroupTabsMenuItemView.h"
#import "StockBarAppDelegate.h"
#import "StockMenuItemView.h"
#import "StockQuote.h"
#import "StockSearchWindowController.h"
#import "TencentQuoteService.h"
#import "WatchlistStore.h"

// Exercise the controller without starting a status item, login item or network request.
@interface StockBarAppDelegate (GroupSelectionTest)
- (void)refreshAfterGroupChange;
- (void)refreshDisplayedQuotes;
- (void)groupTabsView:(GroupTabsMenuItemView *)view didSelectGroup:(NSString *)identifier;
- (void)addStockMenuItemView:(AddStockMenuItemView *)view didSubmitInput:(NSString *)input;
- (void)stockMenuItemViewDidRequestDelete:(StockMenuItemView *)view;
- (void)stockSearchController:(StockSearchWindowController *)controller didChooseResult:(StockSearchResult *)result
             groupIdentifier:(NSString *)groupIdentifier completion:(SearchAddCompletion)completion;
+ (void)seedRightSidePositionInDefaults:(NSUserDefaults *)defaults;
@end

@interface SelectionTestApp : StockBarAppDelegate
@property (nonatomic) NSUInteger menuPresentationRequests;
@end
@implementation SelectionTestApp
- (void)showMenuAfterReopen { self.menuPresentationRequests++; }
@end

@interface OfflineQuoteService : TencentQuoteService
@property (nonatomic, copy) QuoteValidationHandler pendingValidation;
@end
@implementation OfflineQuoteService
- (void)refresh {}
- (void)validateCode:(NSString *)code completion:(QuoteValidationHandler)completion {
    (void)code;
    self.pendingValidation = completion;
}
@end

static void Check(BOOL condition, NSString *message) {
    if (!condition) {
        fprintf(stderr, "%s\n", message.UTF8String);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *suite = [@"dev.talon.stockbar.selection-test." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        [StockBarAppDelegate seedRightSidePositionInDefaults:defaults];
        Check([defaults doubleForKey:@"NSStatusItem Preferred Position StockBar"] == 1.0, @"Right-side default not seeded");
        [defaults setDouble:250.0 forKey:@"NSStatusItem Preferred Position StockBar"];
        [StockBarAppDelegate seedRightSidePositionInDefaults:defaults];
        Check([defaults doubleForKey:@"NSStatusItem Preferred Position StockBar"] == 250.0, @"User's menu bar position was overwritten on the next launch");
        [defaults setObject:@[@"512890"] forKey:@"watchlist.codes.v1"];
        WatchlistStore *store = [[WatchlistStore alloc] initWithDefaults:defaults];
        NSString *fundGroup = [store createGroupWithName:@"场内基金" error:nil];
        [store addCode:@"512890"];
        [store addCode:@"159915"];
        [store selectGroup:WatchlistDefaultGroupIdentifier];

        SelectionTestApp *app = [[SelectionTestApp alloc] init];
        [app applicationShouldHandleReopen:NSApp hasVisibleWindows:NO];
        NSDate *reopenDeadline = [NSDate dateWithTimeIntervalSinceNow:0.2];
        while (reopenDeadline.timeIntervalSinceNow > 0.0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        Check(app.menuPresentationRequests == 0, @"Reopening unexpectedly displayed the quote menu");
        [app setValue:store forKey:@"watchlistStore"];
        OfflineQuoteService *service = [[OfflineQuoteService alloc] initWithCodes:@[QuoteCodeSSECompositeIndex, @"512890", @"159915"]];
        [app setValue:service forKey:@"quoteService"];
        NSMutableDictionary *quotes = [NSMutableDictionary dictionary];
        for (NSString *code in service.codes) {
            quotes[code] = [[StockQuote alloc] initWithName:code code:code previousClose:1.0 price:1.237];
        }
        [app setValue:quotes forKey:@"quotesByCode"];
        NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Test"];
        NSMenuItem *status = [[NSMenuItem alloc] initWithTitle:@"行情更新" action:nil keyEquivalent:@""];
        [menu addItem:status];
        [app setValue:menu forKey:@"statusMenu"];
        [app setValue:status forKey:@"quoteStatusMenuItem"];
        [app setValue:[NSMutableArray array] forKey:@"stockMenuItems"];
        GroupTabsMenuItemView *tabs = [[GroupTabsMenuItemView alloc] initWithFrame:NSZeroRect];
        [app setValue:tabs forKey:@"groupTabsView"];
        [app refreshAfterGroupChange];
        NSArray<StockQuote *> *displayed = [app valueForKey:@"latestQuotes"];
        Check(displayed.count == 2 && [displayed[0].code isEqualToString:QuoteCodeSSECompositeIndex], @"Default group/index display incorrect");
        NSMenuItem *originalRow = [[app valueForKey:@"stockMenuItems"] lastObject];
        [app refreshDisplayedQuotes];
        Check([[app valueForKey:@"stockMenuItems"] lastObject] == originalRow, @"Quote update rebuilt rows and reset mouse tracking");

        [app groupTabsView:tabs didSelectGroup:fundGroup];
        displayed = [app valueForKey:@"latestQuotes"];
        Check(displayed.count == 3 && [displayed[2].code isEqualToString:@"159915"], @"Switch did not filter cached quotes");
        StockMenuItemView *sharedFundView = [[StockMenuItemView alloc] initWithQuote:quotes[@"512890"]];
        [app stockMenuItemViewDidRequestDelete:sharedFundView];
        NSDate *deleteDeadline = [NSDate dateWithTimeIntervalSinceNow:1.0];
        while ([store containsCode:@"512890"] && deleteDeadline.timeIntervalSinceNow > 0.0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        Check(![store containsCode:@"512890"], @"Row delete failed in selected group");
        [store selectGroup:WatchlistDefaultGroupIdentifier];
        Check([store containsCode:@"512890"], @"Row delete affected default group");

        [app groupTabsView:tabs didSelectGroup:fundGroup];
        AddStockMenuItemView *addView = [[AddStockMenuItemView alloc] initWithFrame:NSZeroRect];
        [app addStockMenuItemView:addView didSubmitInput:@"510310"];
        Check(service.pendingValidation != nil, @"Add validation was not requested");
        [app groupTabsView:tabs didSelectGroup:WatchlistDefaultGroupIdentifier];
        StockQuote *validated = [[StockQuote alloc] initWithName:@"沪深300ETF" code:@"510310" previousClose:3.97 price:3.985];
        service.pendingValidation(validated, nil);
        Check(![store containsCode:@"510310"], @"Validation completed in the wrong group after switching tabs");
        [store selectGroup:fundGroup];
        Check([store containsCode:@"510310"], @"Validated code not added to original target group");

        StockSearchWindowController *search = [[StockSearchWindowController alloc] init];
        [search.window orderFront:nil];
        [store selectGroup:WatchlistDefaultGroupIdentifier];
        StockSearchResult *candidate = [[StockSearchResult alloc] initWithCode:@"300308" name:@"中际旭创"];
        __block BOOL searchAdded = NO;
        [app stockSearchController:search didChooseResult:candidate groupIdentifier:fundGroup completion:^(NSError *error) {
            searchAdded = error == nil;
        }];
        service.pendingValidation([[StockQuote alloc] initWithName:candidate.name code:candidate.code previousClose:100 price:101], nil);
        Check(searchAdded && ![store containsCode:candidate.code], @"Search candidate added to selected group instead of captured target");
        [store selectGroup:fundGroup];
        Check([store containsCode:candidate.code], @"Search candidate not added to target group");
        __block BOOL duplicateRejected = NO;
        [app stockSearchController:search didChooseResult:candidate groupIdentifier:fundGroup completion:^(NSError *error) {
            duplicateRejected = error != nil;
        }];
        Check(duplicateRejected, @"Duplicate search candidate accepted");
        candidate = [[StockSearchResult alloc] initWithCode:@"600519" name:@"贵州茅台"];
        __block BOOL cancelled = NO;
        [app stockSearchController:search didChooseResult:candidate groupIdentifier:fundGroup completion:^(NSError *error) {
            cancelled = error != nil;
        }];
        [search close];
        service.pendingValidation([[StockQuote alloc] initWithName:candidate.name code:candidate.code previousClose:100 price:101], nil);
        Check(cancelled && ![store containsCode:@"600519"], @"Closing search did not cancel pending add");
        [defaults removePersistentDomainForName:suite];
        puts("Group selection: display, deletion, async routing, search selection, duplicates and cancellation passed");
    }
    return 0;
}
