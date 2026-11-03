#import <Foundation/Foundation.h>
#import "StockSearchService.h"

@interface StockSearchService (Testing)
- (instancetype)initWithSessionConfiguration:(NSURLSessionConfiguration *)configuration;
+ (nullable NSArray<StockSearchResult *> *)parseTencentData:(NSData *)data;
+ (nullable NSArray<StockSearchResult *> *)parseEastmoneyData:(NSData *)data;
@end

static void Check(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr, "%s\n", message.UTF8String); exit(1); }
}

static NSData *TencentData(NSString *payload) {
    NSData *json = [NSJSONSerialization dataWithJSONObject:@[payload] options:0 error:nil];
    NSString *array = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    NSString *quoted = [array substringWithRange:NSMakeRange(1, array.length - 2)];
    return [[NSString stringWithFormat:@"v_hint=%@;", quoted] dataUsingEncoding:NSUTF8StringEncoding];
}

static NSData *EastmoneyData(NSArray *records) {
    return [NSJSONSerialization dataWithJSONObject:@{@"QuotationCodeTable": @{@"Data": records}} options:0 error:nil];
}

static NSString *StubMode;
static NSMutableArray<NSString *> *RequestedHosts;

@interface SearchStubProtocol : NSURLProtocol
@end
@implementation SearchStubProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { (void)request; return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    @synchronized (RequestedHosts) { [RequestedHosts addObject:self.request.URL.host]; }
    BOOL fallback = [StubMode isEqualToString:@"fallback"];
    BOOL failing = [StubMode isEqualToString:@"error"];
    NSData *data;
    if ([self.request.URL.host isEqualToString:@"smartbox.gtimg.cn"]) {
        data = TencentData(fallback ? @"N" : @"sz~300308~中际旭创~zjxc~GP-A");
    } else {
        data = EastmoneyData(@[@{@"Code": @"512890", @"Name": @"红利低波ETF", @"Classify": @"Fund", @"QuoteID": @"1.512890"}]);
    }
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:failing ? 503 : 200 HTTPVersion:@"HTTP/1.1" headerFields:nil];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

static void RunUntil(BOOL (^condition)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3.0];
    while (!condition() && deadline.timeIntervalSinceNow > 0.0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    Check(condition(), @"Search callback timed out");
}

int main(void) {
    @autoreleasepool {
        NSData *unicode = [@"v_hint=\"sz~300308~\\u4e2d\\u9645\\u65ed\\u521b~zjxc~GP-A\";" dataUsingEncoding:NSUTF8StringEncoding];
        Check([[StockSearchService parseTencentData:unicode].firstObject.name isEqualToString:@"中际旭创"], @"Unicode escaped names not decoded");
        NSArray *tencent = [StockSearchService parseTencentData:TencentData(@"sz~300308~中际旭创~zjxc~GP-A^hk~03308~同名港股~zjxc~GP^sz~399997~中证白酒~zzbj~ZS^jj~012414~场外基金~jj~KJ^sh~512890~红利低波ETF~hldb~ETF^sz~161725~白酒LOF~bjjj~LOF^sz~300308~重复~zjxc~GP-A^sh~300308~市场错误~wrong~GP-A")];
        Check(tencent.count == 3, @"Tencent filtering/deduplication failed");
        Check([[(StockSearchResult *)tencent[1] marketLabel] isEqualToString:@"沪基"], @"ETF market label incorrect");
        Check([StockSearchService parseTencentData:TencentData(@"N")].count == 0, @"Empty search not handled");
        Check([StockSearchService parseTencentData:[@"invalid" dataUsingEncoding:NSUTF8StringEncoding]] == nil, @"Malformed search accepted");

        NSArray *east = [StockSearchService parseEastmoneyData:EastmoneyData(@[
            @{@"Code": @"300308", @"Name": @"中际旭创", @"Classify": @"AStock", @"QuoteID": @"0.300308"},
            @{@"Code": @"512890", @"Name": @"红利低波ETF", @"Classify": @"Fund", @"QuoteID": @"1.512890"},
            @{@"Code": @"920002", @"Name": @"万达轴承", @"Classify": @"NEEQ", @"SecurityTypeName": @"京A", @"QuoteID": @"0.920002"},
            @{@"Code": @"830001", @"Name": @"未上市新三板", @"Classify": @"NEEQ", @"SecurityTypeName": @"三板", @"QuoteID": @"0.830001"},
            @{@"Code": @"000001", @"Name": @"上证指数", @"Classify": @"Index", @"QuoteID": @"1.000001"},
            @{@"Code": @"110022", @"Name": @"场外基金", @"Classify": @"Fund", @"QuoteID": @"0.110022"},
            @{@"Code": @"512890", @"Name": @"错误市场", @"Classify": @"Fund", @"QuoteID": @"0.512890"},
            @{@"Code": @"300308", @"Name": NSNull.null, @"Classify": @"AStock", @"QuoteID": @"0.300308"}
        ])];
        Check(east.count == 3, @"Eastmoney market/type filtering failed");
        Check([[(StockSearchResult *)east[2] marketLabel] isEqualToString:@"北A"], @"Listed Beijing stock rejected");
        NSMutableArray *many = [NSMutableArray array];
        for (NSUInteger i = 0; i < 15; i++) {
            NSString *code = [NSString stringWithFormat:@"600%03lu", (unsigned long)i];
            [many addObject:@{@"Code": code, @"Name": code, @"Classify": @"AStock", @"QuoteID": [@"1." stringByAppendingString:code]}];
        }
        Check(StockSearchResultLimit == 8 && [StockSearchService parseEastmoneyData:EastmoneyData(many)].count == StockSearchResultLimit, @"Eight-candidate limit not enforced");

        RequestedHosts = [NSMutableArray array];
        NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        configuration.protocolClasses = @[SearchStubProtocol.class];
        StockSearchService *service = [[StockSearchService alloc] initWithSessionConfiguration:configuration];
        StubMode = @"fallback";
        __block BOOL done = NO;
        __block BOOL valid = NO;
        [service searchQuery:@"红利低波" completion:^(NSArray<StockSearchResult *> *results, NSError *error) {
            valid = !error && [results.firstObject.code isEqualToString:@"512890"];
            done = YES;
        }];
        RunUntil(^BOOL{ return done; });
        Check(valid && RequestedHosts.count == 2, @"Fallback search failed");

        StubMode = @"normal";
        done = NO;
        __block BOOL staleDelivered = NO;
        [service searchQuery:@"old" completion:^(NSArray *results, NSError *error) {
            (void)results; (void)error; staleDelivered = YES;
        }];
        [service searchQuery:@"zjxc" completion:^(NSArray<StockSearchResult *> *results, NSError *error) {
            valid = !error && [results.firstObject.code isEqualToString:@"300308"];
            done = YES;
        }];
        RunUntil(^BOOL{ return done; });
        Check(valid && !staleDelivered, @"Old query overwrote latest results");
        StubMode = @"error";
        done = NO;
        [service searchQuery:@"fail" completion:^(NSArray *results, NSError *error) {
            valid = error != nil && results.count == 0;
            done = YES;
        }];
        RunUntil(^BOOL{ return done; });
        Check(valid, @"Provider errors not reported");
        [service cancel];
        puts("Search: names, types, markets, deduplication, fallback, stale queries and errors passed");
    }
    return 0;
}
