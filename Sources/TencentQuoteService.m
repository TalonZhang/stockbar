#import "TencentQuoteService.h"

#import <CoreFoundation/CoreFoundation.h>
#import <float.h>

#import "StockQuote.h"
#import "WatchlistStore.h"

static NSString *const QuoteServiceErrorDomain = @"dev.touchbarstocks.quote";
static NSString *const QuoteSourceDefaultsKey = @"quote.source.v1";
NSString * const QuoteCodeSSECompositeIndex = @"INDEX_SH000001";

typedef void (^ProviderCompletion)(NSDictionary<NSString *, StockQuote *> *quotes, NSError *_Nullable error);
typedef void (^SourceCompletion)(NSDictionary<NSString *, StockQuote *> *quotes, NSError *_Nullable error, QuoteSource effectiveSource);

@interface TencentQuoteService ()

@property (nonatomic, copy) NSArray<NSString *> *codes;
@property (nonatomic, strong) NSMutableDictionary<NSString *, StockQuote *> *quoteCache;
@property (nonatomic, strong, nullable) NSTimer *timer;
@property (nonatomic, strong, nullable) NSDate *lastAttempt;
@property (nonatomic) BOOL requestInFlight;

@end

@implementation TencentQuoteService

- (instancetype)initWithCodes:(NSArray<NSString *> *)codes {
    self = [super init];
    if (self) {
        _codes = [codes copy];
        _quoteCache = [NSMutableDictionary dictionary];
        NSInteger storedSource = [[NSUserDefaults standardUserDefaults] integerForKey:QuoteSourceDefaultsKey];
        _source = storedSource >= QuoteSourceAutomatic && storedSource <= QuoteSourceEastmoney
            ? (QuoteSource)storedSource
            : QuoteSourceAutomatic;
    }
    return self;
}

+ (NSString *)displayNameForSource:(QuoteSource)source {
    switch (source) {
        case QuoteSourceTencent:
            return @"腾讯财经";
        case QuoteSourceEastmoney:
            return @"东方财富";
        default:
            return @"自动切换";
    }
}

- (void)setSource:(QuoteSource)source {
    if (source < QuoteSourceAutomatic || source > QuoteSourceEastmoney) {
        source = QuoteSourceAutomatic;
    }
    _source = source;
    [[NSUserDefaults standardUserDefaults] setInteger:source forKey:QuoteSourceDefaultsKey];
    self.lastAttempt = nil;
    if (self.timer) {
        [self refresh];
    }
}

- (void)setCodes:(NSArray<NSString *> *)codes {
    _codes = [codes copy];
    NSMutableSet<NSString *> *activeCodes = [NSMutableSet setWithArray:codes];
    for (NSString *cachedCode in [self.quoteCache.allKeys copy]) {
        if (![activeCodes containsObject:cachedCode]) {
            [self.quoteCache removeObjectForKey:cachedCode];
        }
    }
    [self emitQuotesWithStatus:@"自选股已更新"];
}

- (void)start {
    if (self.timer) {
        return;
    }
    [self refresh];
    self.timer = [NSTimer timerWithTimeInterval:5.0
                                         target:self
                                       selector:@selector(timerTick:)
                                       userInfo:nil
                                        repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
}

- (void)stop {
    [self.timer invalidate];
    self.timer = nil;
}

- (void)timerTick:(NSTimer *)timer {
    (void)timer;
    NSTimeInterval secondsSinceLastAttempt = self.lastAttempt ? -[self.lastAttempt timeIntervalSinceNow] : DBL_MAX;
    if ([self isWithinMarketRefreshWindow] || secondsSinceLastAttempt >= 60.0) {
        [self refresh];
    }
}

- (void)refresh {
    if (self.requestInFlight) {
        return;
    }
    if (self.codes.count == 0) {
        [self emitQuotesWithStatus:@"请添加自选股"];
        return;
    }

    self.requestInFlight = YES;
    self.lastAttempt = [NSDate date];
    NSArray<NSString *> *requestedCodes = self.codes;
    [self requestQuotesForCodes:requestedCodes completion:^(NSDictionary<NSString *, StockQuote *> *quotes, NSError *error, QuoteSource effectiveSource) {
        self.requestInFlight = NO;
        if (error) {
            [self emitQuotesWithStatus:[NSString stringWithFormat:@"行情获取失败 · %@", error.localizedDescription]];
            return;
        }

        [self.quoteCache addEntriesFromDictionary:quotes];
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.locale = [NSLocale localeWithLocaleIdentifier:@"zh_CN"];
        formatter.dateFormat = @"HH:mm:ss";
        NSString *status = [NSString stringWithFormat:@"行情更新 %@ · %@",
                            [formatter stringFromDate:[NSDate date]],
                            [TencentQuoteService displayNameForSource:effectiveSource]];
        [self emitQuotesWithStatus:status];
    }];
}

- (void)validateCode:(NSString *)code completion:(QuoteValidationHandler)completion {
    [self requestQuotesForCodes:@[code] completion:^(NSDictionary<NSString *, StockQuote *> *quotes, NSError *error, QuoteSource effectiveSource) {
        (void)effectiveSource;
        StockQuote *quote = quotes[code];
        if (!quote && !error) {
            error = [NSError errorWithDomain:QuoteServiceErrorDomain
                                        code:2
                                    userInfo:@{NSLocalizedDescriptionKey: @"未找到该股票或场内基金代码"}];
        }
        completion(quote, error);
    }];
}

- (void)requestQuotesForCodes:(NSArray<NSString *> *)codes
                    completion:(SourceCompletion)completion {
    if (self.source == QuoteSourceTencent) {
        [self requestTencentQuotesForCodes:codes completion:^(NSDictionary<NSString *, StockQuote *> *quotes, NSError *error) {
            completion(quotes, error, QuoteSourceTencent);
        }];
        return;
    }
    if (self.source == QuoteSourceEastmoney) {
        [self requestEastmoneyQuotesForCodes:codes completion:^(NSDictionary<NSString *, StockQuote *> *quotes, NSError *error) {
            completion(quotes, error, QuoteSourceEastmoney);
        }];
        return;
    }

    [self requestTencentQuotesForCodes:codes completion:^(NSDictionary<NSString *, StockQuote *> *tencentQuotes, NSError *tencentError) {
        if (!tencentError && tencentQuotes.count >= codes.count) {
            completion(tencentQuotes, nil, QuoteSourceTencent);
            return;
        }

        [self requestEastmoneyQuotesForCodes:codes completion:^(NSDictionary<NSString *, StockQuote *> *eastmoneyQuotes, NSError *eastmoneyError) {
            NSMutableDictionary<NSString *, StockQuote *> *merged = [tencentQuotes mutableCopy];
            [merged addEntriesFromDictionary:eastmoneyQuotes];
            if (merged.count > 0) {
                completion(merged, nil, QuoteSourceEastmoney);
            } else {
                NSError *error = eastmoneyError ? eastmoneyError : tencentError;
                completion(@{}, error, QuoteSourceAutomatic);
            }
        }];
    }];
}

- (void)requestTencentQuotesForCodes:(NSArray<NSString *> *)codes completion:(ProviderCompletion)completion {
    NSMutableArray<NSString *> *symbols = [NSMutableArray arrayWithCapacity:codes.count];
    NSMutableDictionary<NSString *, NSString *> *codesBySymbol = [NSMutableDictionary dictionaryWithCapacity:codes.count];
    for (NSString *code in codes) {
        NSString *symbol = [code isEqualToString:QuoteCodeSSECompositeIndex]
            ? @"sh000001"
            : [WatchlistStore marketSymbolForCode:code];
        if (symbol) {
            [symbols addObject:symbol];
            codesBySymbol[symbol] = code;
        }
    }
    if (symbols.count == 0) {
        NSError *error = [NSError errorWithDomain:QuoteServiceErrorDomain
                                             code:1
                                         userInfo:@{NSLocalizedDescriptionKey: @"没有有效的股票或场内基金代码"}];
        completion(@{}, error);
        return;
    }

    NSString *urlString = [NSString stringWithFormat:@"https://qt.gtimg.cn/q=%@", [symbols componentsJoinedByString:@","]];
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 10.0;
    [request setValue:@"https://gu.qq.com/" forHTTPHeaderField:@"Referer"];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *networkError) {
        NSError *responseError = networkError ? networkError : [self HTTPErrorForResponse:response sourceName:@"腾讯财经"];
        NSDictionary<NSString *, StockQuote *> *parsedQuotes = responseError
            ? @{}
            : [self parseTencentResponseData:data codesBySymbol:codesBySymbol];
        if (!responseError && parsedQuotes.count == 0) {
            responseError = [self emptyResponseErrorForSource:@"腾讯财经"];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(parsedQuotes, responseError);
        });
    }];
    [task resume];
}

- (void)requestEastmoneyQuotesForCodes:(NSArray<NSString *> *)codes completion:(ProviderCompletion)completion {
    NSMutableArray<NSString *> *securityIDs = [NSMutableArray arrayWithCapacity:codes.count];
    NSMutableDictionary<NSString *, NSString *> *codesBySecurityID = [NSMutableDictionary dictionaryWithCapacity:codes.count];
    for (NSString *code in codes) {
        BOOL isIndex = [code isEqualToString:QuoteCodeSSECompositeIndex];
        NSString *normalized = isIndex
            ? @"000001"
            : [WatchlistStore normalizedCodeFromInput:code];
        if (!normalized) {
            continue;
        }
        NSString *symbol = isIndex ? @"sh000001" : [WatchlistStore marketSymbolForCode:normalized];
        NSString *market = [symbol hasPrefix:@"sh"]
            ? @"1"
            : @"0";
        NSString *securityID = [NSString stringWithFormat:@"%@.%@", market, normalized];
        [securityIDs addObject:securityID];
        codesBySecurityID[securityID] = code;
    }
    if (securityIDs.count == 0) {
        completion(@{}, [NSError errorWithDomain:QuoteServiceErrorDomain
                                             code:1
                                         userInfo:@{NSLocalizedDescriptionKey: @"没有有效的股票或场内基金代码"}]);
        return;
    }

    NSString *urlString = [NSString stringWithFormat:
        @"https://82.push2delay.eastmoney.com/api/qt/ulist.np/get?fltt=2&fields=f12,f13,f14,f2,f3,f18&secids=%@",
        [securityIDs componentsJoinedByString:@","]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:urlString]];
    request.timeoutInterval = 10.0;
    [request setValue:@"https://quote.eastmoney.com/" forHTTPHeaderField:@"Referer"];
    [request setValue:@"Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15"
   forHTTPHeaderField:@"User-Agent"];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                completionHandler:^(NSData *data, NSURLResponse *response, NSError *networkError) {
        NSError *responseError = networkError ? networkError : [self HTTPErrorForResponse:response sourceName:@"东方财富"];
        NSDictionary<NSString *, StockQuote *> *parsedQuotes = responseError
            ? @{}
            : [self parseEastmoneyResponseData:data codesBySecurityID:codesBySecurityID];
        if (!responseError && parsedQuotes.count == 0) {
            responseError = [self emptyResponseErrorForSource:@"东方财富"];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(parsedQuotes, responseError);
        });
    }];
    [task resume];
}

- (NSDictionary<NSString *, StockQuote *> *)parseTencentResponseData:(NSData *)data
                                                        codesBySymbol:(NSDictionary<NSString *, NSString *> *)codesBySymbol {
    if (data.length == 0) {
        return @{};
    }

    NSStringEncoding gb18030 = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
    NSString *text = [[NSString alloc] initWithData:data encoding:gb18030];
    if (!text) {
        return @{};
    }

    NSMutableDictionary<NSString *, StockQuote *> *quotes = [NSMutableDictionary dictionary];
    for (NSString *record in [text componentsSeparatedByString:@";"]) {
        NSRange firstQuote = [record rangeOfString:@"\""];
        NSRange lastQuote = [record rangeOfString:@"\"" options:NSBackwardsSearch];
        if (firstQuote.location == NSNotFound || lastQuote.location == NSNotFound || lastQuote.location <= firstQuote.location) {
            continue;
        }

        NSUInteger start = NSMaxRange(firstQuote);
        NSString *payload = [record substringWithRange:NSMakeRange(start, lastQuote.location - start)];
        NSArray<NSString *> *fields = [payload componentsSeparatedByString:@"~"];
        if (fields.count <= 32) {
            continue;
        }

        NSString *name = fields[1];
        NSString *code = fields[2];
        if (name.length == 0 || code.length != 6) {
            continue;
        }

        double price = [fields[3] doubleValue];
        double previousClose = [fields[4] doubleValue];
        NSString *symbol = nil;
        NSString *prefix = [record substringToIndex:firstQuote.location];
        NSRange symbolMarker = [prefix rangeOfString:@"v_" options:NSBackwardsSearch];
        if (symbolMarker.location != NSNotFound) {
            symbol = [prefix substringFromIndex:NSMaxRange(symbolMarker)];
            symbol = [symbol stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" ="]];
        }
        NSString *logicalCode = symbol.length > 0 ? codesBySymbol[symbol] : nil;
        if (logicalCode.length == 0) {
            logicalCode = code;
        }
        StockQuote *quote = [[StockQuote alloc] initWithName:name code:logicalCode previousClose:previousClose price:price];
        quote.percentChange = [fields[32] doubleValue];
        quote.available = YES;
        quote.updatedAt = [NSDate date];
        quotes[logicalCode] = quote;
    }
    return quotes;
}

- (NSDictionary<NSString *, StockQuote *> *)parseEastmoneyResponseData:(NSData *)data
                                                     codesBySecurityID:(NSDictionary<NSString *, NSString *> *)codesBySecurityID {
    if (data.length == 0) {
        return @{};
    }

    NSError *jsonError = nil;
    NSDictionary *root = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    if (jsonError || ![root isKindOfClass:[NSDictionary class]]) {
        return @{};
    }
    NSDictionary *dataObject = root[@"data"];
    NSArray *records = [dataObject isKindOfClass:[NSDictionary class]] ? dataObject[@"diff"] : nil;
    if (![records isKindOfClass:[NSArray class]]) {
        return @{};
    }

    NSMutableDictionary<NSString *, StockQuote *> *quotes = [NSMutableDictionary dictionary];
    for (NSDictionary *record in records) {
        if (![record isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *code = [record[@"f12"] isKindOfClass:[NSString class]] ? record[@"f12"] : nil;
        id marketValue = record[@"f13"];
        NSString *name = [record[@"f14"] isKindOfClass:[NSString class]] ? record[@"f14"] : nil;
        id priceValue = record[@"f2"];
        id percentValue = record[@"f3"];
        id previousCloseValue = record[@"f18"];
        if (code.length != 6 || name.length == 0
            || ![priceValue respondsToSelector:@selector(doubleValue)]
            || ![previousCloseValue respondsToSelector:@selector(doubleValue)]) {
            continue;
        }

        NSString *securityID = [marketValue respondsToSelector:@selector(integerValue)]
            ? [NSString stringWithFormat:@"%ld.%@", (long)[marketValue integerValue], code]
            : nil;
        NSString *logicalCode = securityID.length > 0 ? codesBySecurityID[securityID] : nil;
        if (logicalCode.length == 0) {
            logicalCode = code;
        }
        StockQuote *quote = [[StockQuote alloc] initWithName:name
                                                        code:logicalCode
                                               previousClose:[previousCloseValue doubleValue]
                                                      price:[priceValue doubleValue]];
        if ([percentValue respondsToSelector:@selector(doubleValue)]) {
            quote.percentChange = [percentValue doubleValue];
        }
        quote.available = YES;
        quote.updatedAt = [NSDate date];
        quotes[logicalCode] = quote;
    }
    return quotes;
}

- (nullable NSError *)HTTPErrorForResponse:(NSURLResponse *)response sourceName:(NSString *)sourceName {
    if (![response isKindOfClass:[NSHTTPURLResponse class]]) {
        return nil;
    }
    NSInteger statusCode = ((NSHTTPURLResponse *)response).statusCode;
    if (statusCode >= 200 && statusCode < 300) {
        return nil;
    }
    return [NSError errorWithDomain:QuoteServiceErrorDomain
                               code:statusCode
                           userInfo:@{NSLocalizedDescriptionKey:
                               [NSString stringWithFormat:@"%@返回 HTTP %ld", sourceName, (long)statusCode]}];
}

- (NSError *)emptyResponseErrorForSource:(NSString *)sourceName {
    return [NSError errorWithDomain:QuoteServiceErrorDomain
                               code:3
                           userInfo:@{NSLocalizedDescriptionKey:
                               [NSString stringWithFormat:@"%@没有返回有效行情", sourceName]}];
}

- (void)emitQuotesWithStatus:(NSString *)status {
    if (!self.updateHandler) {
        return;
    }

    NSMutableArray<StockQuote *> *orderedQuotes = [NSMutableArray arrayWithCapacity:self.codes.count];
    for (NSString *code in self.codes) {
        StockQuote *quote = self.quoteCache[code];
        if (!quote) {
            quote = [[StockQuote alloc] initWithName:code code:code previousClose:0.0 price:0.0];
            quote.available = NO;
        }
        [orderedQuotes addObject:quote];
    }
    self.updateHandler(orderedQuotes, status);
}

- (BOOL)isWithinMarketRefreshWindow {
    NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
    calendar.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    NSDateComponents *components = [calendar components:(NSCalendarUnitWeekday | NSCalendarUnitHour | NSCalendarUnitMinute)
                                                fromDate:[NSDate date]];
    if (components.weekday == 1 || components.weekday == 7) {
        return NO;
    }
    NSInteger minuteOfDay = components.hour * 60 + components.minute;
    BOOL morning = minuteOfDay >= 9 * 60 + 15 && minuteOfDay <= 11 * 60 + 35;
    BOOL afternoon = minuteOfDay >= 12 * 60 + 55 && minuteOfDay <= 15 * 60 + 5;
    return morning || afternoon;
}

@end
