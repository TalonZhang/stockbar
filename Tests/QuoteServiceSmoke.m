#import <Foundation/Foundation.h>

#import "../Sources/StockQuote.h"
#import "../Sources/TencentQuoteService.h"
#import "../Sources/WatchlistStore.h"

static BOOL assertEqualStrings(NSString *actual, NSString *expected, NSString *label) {
    if (![actual isEqualToString:expected]) {
        fprintf(stderr, "%s failed: got %s, expected %s\n",
                label.UTF8String, actual.UTF8String, expected.UTF8String);
        return NO;
    }
    return YES;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        BOOL normalizationOK = YES;
        normalizationOK &= assertEqualStrings([WatchlistStore normalizedCodeFromInput:@"sh600519"], @"600519", @"prefix normalization");
        normalizationOK &= assertEqualStrings([WatchlistStore normalizedCodeFromInput:@"000001.SZ"], @"000001", @"suffix normalization");
        normalizationOK &= assertEqualStrings([WatchlistStore marketSymbolForCode:@"920002"], @"bj920002", @"BSE mapping");
        if (!normalizationOK) {
            return 1;
        }

        NSArray<NSString *> *codes = @[@"600519", @"000001", @"300750", @"920002",
                                      @"512890", @"510310", @"159915", @"161725"];
        TencentQuoteService *service = [[TencentQuoteService alloc] initWithCodes:codes];
        NSString *sourceArgument = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"auto";
        if ([sourceArgument isEqualToString:@"tencent"]) {
            service.source = QuoteSourceTencent;
        } else if ([sourceArgument isEqualToString:@"eastmoney"]) {
            service.source = QuoteSourceEastmoney;
        } else {
            service.source = QuoteSourceAutomatic;
        }
        printf("source=%s\n", [TencentQuoteService displayNameForSource:service.source].UTF8String);
        __block BOOL finished = NO;
        __block BOOL succeeded = NO;
        service.updateHandler = ^(NSArray<StockQuote *> *quotes, NSString *statusText) {
            printf("status=%s\n", statusText.UTF8String);
            NSUInteger availableCount = 0;
            for (StockQuote *quote in quotes) {
                if (quote.isAvailable) {
                    availableCount++;
                    printf("%s %s %s %+.2f%%\n",
                           quote.code.UTF8String,
                           quote.name.UTF8String,
                           quote.formattedPrice.UTF8String,
                           quote.percentChange);
                }
            }
            succeeded = availableCount == codes.count;
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
            fprintf(stderr, "quote smoke test timed out\n");
            return 2;
        }
        if (!succeeded) {
            fprintf(stderr, "quote smoke test returned incomplete data\n");
            return 3;
        }

        // Exercise the same validation endpoint used by the inline add field.
        __block NSUInteger validatedCount = 0;
        __block BOOL validationOK = YES;
        for (NSString *code in @[@"512890", @"510310"]) {
            [service validateCode:code completion:^(StockQuote *quote, NSError *error) {
                BOOL valid = !error && quote.isAvailable && [quote.code isEqualToString:code]
                    && [quote.name containsString:@"ETF"] && quote.price > 0.0;
                validationOK &= valid;
                validatedCount++;
                printf("add validation %s: %s\n", code.UTF8String, valid ? "OK" : "FAILED");
            }];
        }
        NSDate *validationDeadline = [NSDate dateWithTimeIntervalSinceNow:15.0];
        while (validatedCount < 2 && [validationDeadline timeIntervalSinceNow] > 0.0) {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        }
        if (!validationOK || validatedCount != 2) {
            return 4;
        }
        return 0;
    }
}
