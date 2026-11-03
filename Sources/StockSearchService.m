#import "StockSearchService.h"
#import "WatchlistStore.h"
#import <CoreFoundation/CoreFoundation.h>

static NSString * const SearchErrorDomain = @"dev.talon.stockbar.search";
NSUInteger const StockSearchResultLimit = 8;

@implementation StockSearchResult
- (instancetype)initWithCode:(NSString *)code name:(NSString *)name {
    self = [super init];
    if (self) {
        _code = [code copy];
        _name = [name copy];
        NSString *symbol = [WatchlistStore marketSymbolForCode:code];
        if ([WatchlistStore isExchangeTradedFundCode:code]) {
            _marketLabel = [symbol hasPrefix:@"sh"] ? @"沪基" : @"深基";
        } else {
            _marketLabel = [symbol hasPrefix:@"sh"] ? @"沪A" : ([symbol hasPrefix:@"sz"] ? @"深A" : @"北A");
        }
    }
    return self;
}
@end

typedef void (^ProviderSearchCompletion)(NSArray<StockSearchResult *> *_Nullable results, NSError *_Nullable error);

@interface StockSearchService ()
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, strong, nullable) NSURLSessionDataTask *task;
@property (nonatomic) NSUInteger generation;
@end

@implementation StockSearchService

- (instancetype)init {
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.timeoutIntervalForRequest = 8.0;
    configuration.timeoutIntervalForResource = 12.0;
    return [self initWithSessionConfiguration:configuration];
}

- (instancetype)initWithSessionConfiguration:(NSURLSessionConfiguration *)configuration {
    self = [super init];
    if (self) {
        _session = [NSURLSession sessionWithConfiguration:configuration];
    }
    return self;
}

- (void)dealloc {
    [_task cancel];
    [_session invalidateAndCancel];
}

- (void)cancel {
    self.generation++;
    [self.task cancel];
    self.task = nil;
}

- (void)searchQuery:(NSString *)query completion:(StockSearchCompletion)completion {
    [self cancel];
    NSString *trimmed = [query stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSUInteger generation = self.generation;
    if (trimmed.length == 0 || trimmed.length > 64) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.generation == generation) {
                completion(@[], nil);
            }
        });
        return;
    }

    [self requestQuery:trimmed useTencent:YES generation:generation completion:^(NSArray<StockSearchResult *> *results, NSError *error) {
        if (results.count > 0) {
            completion(results, nil);
            return;
        }
        [self requestQuery:trimmed useTencent:NO generation:generation completion:^(NSArray<StockSearchResult *> *fallback, NSError *fallbackError) {
            NSError *finalError = fallbackError && error ? fallbackError : nil;
            completion(fallback ? fallback : @[], finalError);
        }];
    }];
}

- (void)requestQuery:(NSString *)query useTencent:(BOOL)useTencent generation:(NSUInteger)generation completion:(ProviderSearchCompletion)completion {
    NSURLComponents *components = [NSURLComponents componentsWithString:useTencent
        ? @"https://smartbox.gtimg.cn/s3/"
        : @"https://searchapi.eastmoney.com/api/suggest/get"];
    components.queryItems = useTencent
        ? @[[NSURLQueryItem queryItemWithName:@"q" value:query], [NSURLQueryItem queryItemWithName:@"t" value:@"all"]]
        : @[[NSURLQueryItem queryItemWithName:@"input" value:query], [NSURLQueryItem queryItemWithName:@"type" value:@"14"],
            [NSURLQueryItem queryItemWithName:@"count" value:@"10"]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:components.URL];
    [request setValue:useTencent ? @"https://gu.qq.com/" : @"https://quote.eastmoney.com/" forHTTPHeaderField:@"Referer"];
    [request setValue:@"StockBar/0.6" forHTTPHeaderField:@"User-Agent"];

    self.task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *networkError) {
        NSError *error = networkError;
        NSHTTPURLResponse *http = [response isKindOfClass:NSHTTPURLResponse.class] ? (NSHTTPURLResponse *)response : nil;
        if (!error && http && (http.statusCode < 200 || http.statusCode >= 300)) {
            error = [NSError errorWithDomain:SearchErrorDomain code:http.statusCode
                                   userInfo:@{NSLocalizedDescriptionKey: @"搜索服务暂时不可用，请稍后重试。"}];
        }
        NSArray<StockSearchResult *> *results = nil;
        if (!error) {
            results = useTencent ? [StockSearchService parseTencentData:data] : [StockSearchService parseEastmoneyData:data];
            if (!results) {
                error = [NSError errorWithDomain:SearchErrorDomain code:1
                                       userInfo:@{NSLocalizedDescriptionKey: @"搜索数据格式发生变化，请稍后重试或使用代码添加。"}];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.generation) {
                return;
            }
            self.task = nil;
            completion(results, error);
        });
    }];
    [self.task resume];
}

+ (nullable NSArray<StockSearchResult *> *)parseTencentData:(NSData *)data {
    if (data.length == 0) {
        return nil;
    }
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) {
        text = [[NSString alloc] initWithData:data encoding:CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000)];
    }
    if ([text rangeOfString:@"v_hint="].location == NSNotFound) {
        return nil;
    }
    NSRange first = [text rangeOfString:@"\""];
    NSRange last = [text rangeOfString:@"\"" options:NSBackwardsSearch];
    if (first.location == NSNotFound || last.location <= first.location) {
        return nil;
    }
    NSString *quoted = [text substringWithRange:NSMakeRange(first.location, NSMaxRange(last) - first.location)];
    NSData *json = [[NSString stringWithFormat:@"[%@]", quoted] dataUsingEncoding:NSUTF8StringEncoding];
    id decoded = [NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
    if (![decoded isKindOfClass:NSArray.class] || ![[(NSArray *)decoded firstObject] isKindOfClass:NSString.class]) {
        return nil;
    }
    NSString *payload = [(NSArray *)decoded firstObject];
    NSMutableArray *results = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSString *record in [payload componentsSeparatedByString:@"^"]) {
        NSArray<NSString *> *fields = [record componentsSeparatedByString:@"~"];
        if (fields.count < 5) {
            continue;
        }
        NSString *market = fields[0];
        NSString *code = [WatchlistStore normalizedCodeFromInput:fields[1]];
        NSString *name = fields[2];
        NSString *type = fields[4];
        BOOL fund = code && [WatchlistStore isExchangeTradedFundCode:code];
        BOOL supportedType = fund
            ? [@[@"ETF", @"LOF", @"FUND", @"JJCX"] containsObject:type]
            : [type isEqualToString:@"GP-A"];
        NSString *symbol = code ? [WatchlistStore marketSymbolForCode:code] : nil;
        if (!code || name.length == 0 || !supportedType
            || ![symbol isEqualToString:[market stringByAppendingString:code]] || [seen containsObject:code]) {
            continue;
        }
        [seen addObject:code];
        [results addObject:[[StockSearchResult alloc] initWithCode:code name:name]];
        if (results.count == StockSearchResultLimit) {
            break;
        }
    }
    return results;
}

+ (nullable NSArray<StockSearchResult *> *)parseEastmoneyData:(NSData *)data {
    if (data.length == 0) {
        return nil;
    }
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![root isKindOfClass:NSDictionary.class] || ![root[@"QuotationCodeTable"] isKindOfClass:NSDictionary.class]) {
        return nil;
    }
    NSDictionary *table = root[@"QuotationCodeTable"];
    id records = table[@"Data"];
    if (records == NSNull.null) {
        return @[];
    }
    if (![records isKindOfClass:NSArray.class]) {
        return nil;
    }
    NSMutableArray *results = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (id value in records) {
        if (![value isKindOfClass:NSDictionary.class]) {
            continue;
        }
        NSDictionary *record = value;
        NSString *rawCode = record[@"Code"];
        NSString *name = record[@"Name"];
        NSString *type = record[@"Classify"];
        NSString *quoteID = record[@"QuoteID"];
        if (![rawCode isKindOfClass:NSString.class] || ![name isKindOfClass:NSString.class]
            || ![quoteID isKindOfClass:NSString.class] || ![type isKindOfClass:NSString.class]) {
            continue;
        }
        NSString *code = [WatchlistStore normalizedCodeFromInput:rawCode];
        BOOL fund = code && [WatchlistStore isExchangeTradedFundCode:code];
        NSString *symbol = code ? [WatchlistStore marketSymbolForCode:code] : nil;
        NSString *expectedID = [NSString stringWithFormat:@"%@.%@", [symbol hasPrefix:@"sh"] ? @"1" : @"0", code];
        BOOL listedBeijing = [type isEqualToString:@"NEEQ"]
            && [record[@"SecurityTypeName"] isKindOfClass:NSString.class]
            && [record[@"SecurityTypeName"] isEqualToString:@"京A"];
        if (!code || name.length == 0 || ![quoteID isEqualToString:expectedID] || [seen containsObject:code]
            || !(fund ? [type isEqualToString:@"Fund"] : ([type isEqualToString:@"AStock"] || listedBeijing))) {
            continue;
        }
        [seen addObject:code];
        [results addObject:[[StockSearchResult alloc] initWithCode:code name:name]];
        if (results.count == StockSearchResultLimit) {
            break;
        }
    }
    return results;
}

@end
