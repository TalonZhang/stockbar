#import <Foundation/Foundation.h>
#import "StockSearchService.h"

int main(void) {
    @autoreleasepool {
        StockSearchService *service = [[StockSearchService alloc] init];
        NSArray *cases = @[
            @[@"zjxc", @"300308"], @[@"中际旭创", @"300308"],
            @[@"红利低波", @"512890"], @[@"白酒", @"161725"], @[@"920002", @"920002"],
            @[@"没有这只基金xyz", @""]
        ];
        for (NSArray<NSString *> *testCase in cases) {
            __block BOOL done = NO;
            __block BOOL passed = NO;
            [service searchQuery:testCase[0] completion:^(NSArray<StockSearchResult *> *results, NSError *error) {
                passed = !error && (testCase[1].length > 0 ? NO : results.count == 0);
                for (StockSearchResult *result in results) {
                    if ([result.code isEqualToString:testCase[1]]) { passed = YES; }
                }
                if ([testCase[0] isEqualToString:@"红利低波"]) { passed &= results.count > 1; }
                printf("%s: %lu results, %s\n", testCase[0].UTF8String, (unsigned long)results.count, passed ? "OK" : "FAILED");
                done = YES;
            }];
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:25.0];
            while (!done && deadline.timeIntervalSinceNow > 0.0) {
                [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            }
            if (!done || !passed) { return 1; }
        }
    }
    return 0;
}
