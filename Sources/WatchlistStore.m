#import "WatchlistStore.h"

static NSString *const WatchlistDefaultsKey = @"watchlist.codes.v1";

@interface WatchlistStore ()

@property (nonatomic, strong) NSMutableArray<NSString *> *mutableCodes;

@end

@implementation WatchlistStore

- (instancetype)init {
    self = [super init];
    if (self) {
        NSArray *storedCodes = [[NSUserDefaults standardUserDefaults] arrayForKey:WatchlistDefaultsKey];
        if ([storedCodes isKindOfClass:[NSArray class]]) {
            _mutableCodes = [storedCodes mutableCopy];
        } else {
            _mutableCodes = [@[@"600519", @"000001", @"300750"] mutableCopy];
        }
    }
    return self;
}

- (NSArray<NSString *> *)codes {
    return [self.mutableCodes copy];
}

+ (nullable NSString *)normalizedCodeFromInput:(NSString *)input {
    NSString *candidate = [[input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] uppercaseString];
    candidate = [candidate stringByReplacingOccurrencesOfString:@" " withString:@""];

    NSArray<NSString *> *prefixes = @[@"SH", @"SZ", @"BJ"];
    for (NSString *prefix in prefixes) {
        if ([candidate hasPrefix:prefix] && candidate.length > prefix.length) {
            candidate = [candidate substringFromIndex:prefix.length];
            break;
        }
    }

    for (NSString *suffix in @[@".SH", @".SZ", @".BJ"]) {
        if ([candidate hasSuffix:suffix] && candidate.length > suffix.length) {
            candidate = [candidate substringToIndex:candidate.length - suffix.length];
            break;
        }
    }

    if (candidate.length != 6) {
        return nil;
    }
    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if ([candidate rangeOfCharacterFromSet:nonDigits].location != NSNotFound) {
        return nil;
    }

    unichar first = [candidate characterAtIndex:0];
    if (first != '0' && first != '3' && first != '4' && first != '6' && first != '8' && first != '9') {
        return nil;
    }
    return candidate;
}

+ (nullable NSString *)marketSymbolForCode:(NSString *)code {
    NSString *normalized = [self normalizedCodeFromInput:code];
    if (!normalized) {
        return nil;
    }

    unichar first = [normalized characterAtIndex:0];
    NSString *market;
    if (first == '6') {
        market = @"sh";
    } else if (first == '0' || first == '3') {
        market = @"sz";
    } else {
        market = @"bj";
    }
    return [market stringByAppendingString:normalized];
}

- (BOOL)containsCode:(NSString *)code {
    NSString *normalized = [WatchlistStore normalizedCodeFromInput:code];
    return normalized && [self.mutableCodes containsObject:normalized];
}

- (BOOL)addCode:(NSString *)code {
    NSString *normalized = [WatchlistStore normalizedCodeFromInput:code];
    if (!normalized || [self.mutableCodes containsObject:normalized]) {
        return NO;
    }
    [self.mutableCodes addObject:normalized];
    [self persist];
    return YES;
}

- (BOOL)removeCode:(NSString *)code {
    NSString *normalized = [WatchlistStore normalizedCodeFromInput:code];
    if (!normalized || ![self.mutableCodes containsObject:normalized]) {
        return NO;
    }
    [self.mutableCodes removeObject:normalized];
    [self persist];
    return YES;
}

- (BOOL)moveCode:(NSString *)code byOffset:(NSInteger)offset {
    NSString *normalized = [WatchlistStore normalizedCodeFromInput:code];
    if (!normalized || offset == 0) {
        return NO;
    }

    NSUInteger currentIndex = [self.mutableCodes indexOfObject:normalized];
    if (currentIndex == NSNotFound) {
        return NO;
    }

    NSInteger destination = (NSInteger)currentIndex + offset;
    if (destination < 0 || destination >= (NSInteger)self.mutableCodes.count) {
        return NO;
    }

    return [self moveCode:normalized toIndex:(NSUInteger)destination];
}

- (BOOL)moveCode:(NSString *)code toIndex:(NSUInteger)index {
    NSString *normalized = [WatchlistStore normalizedCodeFromInput:code];
    if (!normalized || index >= self.mutableCodes.count) {
        return NO;
    }

    NSUInteger currentIndex = [self.mutableCodes indexOfObject:normalized];
    if (currentIndex == NSNotFound || currentIndex == index) {
        return NO;
    }

    [self.mutableCodes removeObjectAtIndex:currentIndex];
    [self.mutableCodes insertObject:normalized atIndex:index];
    [self persist];
    return YES;
}

- (void)persist {
    [[NSUserDefaults standardUserDefaults] setObject:self.mutableCodes forKey:WatchlistDefaultsKey];
}

@end
