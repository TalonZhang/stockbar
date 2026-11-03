#import <Foundation/Foundation.h>

#import "StockQuote.h"
#import "WatchlistStore.h"

static BOOL Check(BOOL condition, NSString *message) {
    if (!condition) {
        fprintf(stderr, "%s\n", message.UTF8String);
    }
    return condition;
}

int main(void) {
    @autoreleasepool {
        BOOL passed = YES;
        NSDictionary<NSString *, NSString *> *symbols = @{
            @"512890": @"sh512890", @"510310": @"sh510310",
            @"501018": @"sh501018", @"588000": @"sh588000",
            @"159915": @"sz159915", @"161725": @"sz161725",
            @"180101": @"sz180101", @"600519": @"sh600519",
            @"000001": @"sz000001", @"300750": @"sz300750",
            @"920002": @"bj920002", @"830799": @"bj830799"
        };
        for (NSString *code in symbols) {
            passed &= Check([[WatchlistStore marketSymbolForCode:code] isEqualToString:symbols[code]],
                            [NSString stringWithFormat:@"Incorrect exchange for %@", code]);
        }
        passed &= Check([[WatchlistStore normalizedCodeFromInput:@"  sh512890  "] isEqualToString:@"512890"], @"SH fund prefix rejected");
        passed &= Check([[WatchlistStore normalizedCodeFromInput:@"159915.SZ"] isEqualToString:@"159915"], @"SZ fund suffix rejected");
        for (NSString *input in @[@"110022", @"123456", @"51289", @"5128901", @"51A890", @"５１２８９０"]) {
            passed &= Check([WatchlistStore normalizedCodeFromInput:input] == nil,
                            [NSString stringWithFormat:@"Invalid/unlisted code accepted: %@", input]);
        }

        StockQuote *fund = [[StockQuote alloc] initWithName:@"ETF" code:@"512890" previousClose:1.230 price:1.237];
        passed &= Check([fund.formattedPrice isEqualToString:@"1.237"], @"ETF third decimal lost");
        StockQuote *lof = [[StockQuote alloc] initWithName:@"LOF" code:@"161725" previousClose:0.580 price:0.586];
        passed &= Check([lof.formattedPrice isEqualToString:@"0.586"], @"LOF precision incorrect");
        fund.price = 3.970;
        passed &= Check([fund.formattedPrice isEqualToString:@"3.970"], @"Fund trailing zero lost");
        fund.available = NO;
        passed &= Check([fund.formattedPrice isEqualToString:@"--"], @"Unavailable quote displayed as valid");
        StockQuote *stock = [[StockQuote alloc] initWithName:@"平安银行" code:@"000001" previousClose:10 price:11.2];
        passed &= Check([stock.formattedPrice isEqualToString:@"11.20"], @"Stock precision changed");
        StockQuote *index = [[StockQuote alloc] initWithName:@"上证指数" code:@"INDEX_SH000001" previousClose:3900 price:3920.17];
        passed &= Check([index.formattedPrice isEqualToString:@"3920.17"], @"Index precision changed");
        if (!passed) {
            return 1;
        }
        puts("Fund support: mapping, validation and display precision passed");
    }
    return 0;
}
