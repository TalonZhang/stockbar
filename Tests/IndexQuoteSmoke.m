#import <Foundation/Foundation.h>

#import "StockQuote.h"
#import "TencentQuoteService.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSArray<NSString *> *codes = @[QuoteCodeSSECompositeIndex, @"000001"];
        TencentQuoteService *service = [[TencentQuoteService alloc] initWithCodes:codes];
        NSString *source = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"auto";
        if ([source isEqualToString:@"tencent"]) {
            service.source = QuoteSourceTencent;
        } else if ([source isEqualToString:@"eastmoney"]) {
            service.source = QuoteSourceEastmoney;
        } else {
            service.source = QuoteSourceAutomatic;
        }

        __block BOOL finished = NO;
        __block BOOL succeeded = NO;
        service.updateHandler = ^(NSArray<StockQuote *> *quotes, NSString *statusText) {
            if (quotes.count != 2 || !quotes[0].isAvailable || !quotes[1].isAvailable) {
                finished = YES;
                return;
            }
            StockQuote *index = quotes[0];
            StockQuote *stock = quotes[1];
            succeeded = [index.code isEqualToString:QuoteCodeSSECompositeIndex]
                && [index.name containsString:@"上证"]
                && [stock.code isEqualToString:@"000001"]
                && ![stock.name isEqualToString:index.name];
            printf("%s · %s %.2f %+.2f%% · %s %.2f %+.2f%%\n",
                   statusText.UTF8String,
                   index.name.UTF8String,
                   index.price,
                   index.percentChange,
                   stock.name.UTF8String,
                   stock.price,
                   stock.percentChange);
            finished = YES;
        };
        [service start];

        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:12.0];
        while (!finished && [deadline timeIntervalSinceNow] > 0.0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
        [service stop];
        if (!finished) {
            fprintf(stderr, "index quote smoke test timed out\n");
            return 2;
        }
        if (!succeeded) {
            fprintf(stderr, "index and stock codes were not kept distinct\n");
            return 3;
        }
    }
    return 0;
}
