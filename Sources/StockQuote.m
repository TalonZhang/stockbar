#import "StockQuote.h"
#import "WatchlistStore.h"

@implementation StockQuote

- (NSString *)formattedPrice {
    if (!self.isAvailable) {
        return @"--";
    }
    return [WatchlistStore isExchangeTradedFundCode:self.code]
        ? [NSString stringWithFormat:@"%.3f", self.price]
        : [NSString stringWithFormat:@"%.2f", self.price];
}

- (instancetype)initWithName:(NSString *)name
                         code:(NSString *)code
                previousClose:(double)previousClose
                       price:(double)price {
    self = [super init];
    if (self) {
        _name = [name copy];
        _code = [code copy];
        _previousClose = previousClose;
        _price = price;
        _percentChange = previousClose == 0.0 ? 0.0 : (price - previousClose) / previousClose * 100.0;
        _available = YES;
        _updatedAt = [NSDate date];
    }
    return self;
}

@end
