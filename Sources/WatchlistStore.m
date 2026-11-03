#import "WatchlistStore.h"

static NSString *const WatchlistDefaultsKey = @"watchlist.codes.v1";
static NSString *const WatchlistGroupsKey = @"watchlist.groups.v1";
static NSString *const SelectedGroupKey = @"watchlist.selectedGroup.v1";
NSString * const WatchlistDefaultGroupIdentifier = @"default";

@interface WatchlistGroup ()
@property (nonatomic, copy) NSString *identifier;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSArray<NSString *> *codes;
@end

@implementation WatchlistGroup
@end

@interface WatchlistStore ()

@property (nonatomic, strong) NSUserDefaults *defaults;
@property (nonatomic, strong) NSMutableArray<WatchlistGroup *> *mutableGroups;
@property (nonatomic, copy) NSString *selectedGroupIdentifier;

@end

@implementation WatchlistStore

- (instancetype)init {
    return [self initWithDefaults:NSUserDefaults.standardUserDefaults];
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    self = [super init];
    if (self) {
        _defaults = defaults;
        _mutableGroups = [NSMutableArray array];
        NSArray *storedGroups = [defaults arrayForKey:WatchlistGroupsKey];
        for (id value in storedGroups) {
            if (![value isKindOfClass:NSDictionary.class]) {
                continue;
            }
            NSDictionary *record = value;
            NSString *identifier = record[@"id"];
            NSString *name = record[@"name"];
            if (![identifier isKindOfClass:NSString.class] || identifier.length == 0
                || ![name isKindOfClass:NSString.class] || name.length == 0
                || [self groupForIdentifier:identifier]) {
                continue;
            }
            WatchlistGroup *group = [[WatchlistGroup alloc] init];
            group.identifier = identifier;
            group.name = [identifier isEqualToString:WatchlistDefaultGroupIdentifier] ? @"自选" : name;
            group.codes = [self cleanCodes:record[@"codes"]];
            [_mutableGroups addObject:group];
        }
        if (![self groupForIdentifier:WatchlistDefaultGroupIdentifier]) {
            NSArray *legacy = [defaults arrayForKey:WatchlistDefaultsKey];
            WatchlistGroup *group = [[WatchlistGroup alloc] init];
            group.identifier = WatchlistDefaultGroupIdentifier;
            group.name = @"自选";
            group.codes = legacy ? [self cleanCodes:legacy] : @[@"600519", @"000001", @"300750"];
            [_mutableGroups insertObject:group atIndex:0];
        }
        NSString *selected = [defaults stringForKey:SelectedGroupKey];
        _selectedGroupIdentifier = [self groupForIdentifier:selected] ? selected : WatchlistDefaultGroupIdentifier;
        [self persist];
    }
    return self;
}

- (NSArray<NSString *> *)codes {
    return [[self groupForIdentifier:self.selectedGroupIdentifier].codes copy];
}

- (NSArray<NSString *> *)allCodes {
    NSMutableOrderedSet<NSString *> *codes = [NSMutableOrderedSet orderedSet];
    for (WatchlistGroup *group in self.mutableGroups) {
        [codes addObjectsFromArray:group.codes];
    }
    return codes.array;
}

- (NSArray<WatchlistGroup *> *)groups {
    NSMutableArray *snapshots = [NSMutableArray arrayWithCapacity:self.mutableGroups.count];
    for (WatchlistGroup *group in self.mutableGroups) {
        WatchlistGroup *snapshot = [[WatchlistGroup alloc] init];
        snapshot.identifier = group.identifier;
        snapshot.name = group.name;
        snapshot.codes = group.codes;
        [snapshots addObject:snapshot];
    }
    return snapshots;
}

- (NSString *)selectedGroupName {
    return [self groupForIdentifier:self.selectedGroupIdentifier].name;
}

- (nullable WatchlistGroup *)groupForIdentifier:(nullable NSString *)identifier {
    for (WatchlistGroup *group in self.mutableGroups) {
        if ([group.identifier isEqualToString:identifier]) {
            return group;
        }
    }
    return nil;
}

- (NSArray<NSString *> *)cleanCodes:(id)value {
    NSMutableOrderedSet *codes = [NSMutableOrderedSet orderedSet];
    if ([value isKindOfClass:NSArray.class]) {
        for (id input in value) {
            if (![input isKindOfClass:NSString.class]) {
                continue;
            }
            NSString *code = [WatchlistStore normalizedCodeFromInput:input];
            if (code) {
                [codes addObject:code];
            }
        }
    }
    return codes.array;
}

+ (NSString *)displayNameForGroupName:(NSString *)name {
    __block NSUInteger count = 0;
    __block NSUInteger end = 0;
    [name enumerateSubstringsInRange:NSMakeRange(0, name.length)
                            options:NSStringEnumerationByComposedCharacterSequences
                         usingBlock:^(NSString *substring, NSRange range, NSRange enclosingRange, BOOL *stop) {
        (void)substring;
        (void)enclosingRange;
        end = NSMaxRange(range);
        *stop = ++count == 4;
    }];
    return [name substringToIndex:end];
}

- (nullable NSString *)validGroupName:(NSString *)name excludingGroup:(nullable NSString *)identifier error:(NSError **)error {
    NSString *trimmed = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    __block NSUInteger count = 0;
    [trimmed enumerateSubstringsInRange:NSMakeRange(0, trimmed.length)
                               options:NSStringEnumerationByComposedCharacterSequences
                            usingBlock:^(NSString *substring, NSRange range, NSRange enclosingRange, BOOL *stop) {
        (void)substring; (void)range; (void)enclosingRange; (void)stop;
        count++;
    }];
    NSString *message = nil;
    if (count == 0 || count > 10) {
        message = @"分组名称需要 1～10 个字。";
    } else if ([trimmed rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) {
        message = @"分组名称不能包含换行或控制字符。";
    } else {
        for (WatchlistGroup *group in self.mutableGroups) {
            if (![group.identifier isEqualToString:identifier]
                && [group.name caseInsensitiveCompare:trimmed] == NSOrderedSame) {
                message = @"已经存在同名分组，请换一个名称。";
                break;
            }
        }
    }
    if (message) {
        if (error) {
            *error = [NSError errorWithDomain:@"dev.talon.stockbar.groups" code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
        }
        return nil;
    }
    return trimmed;
}

- (BOOL)selectGroup:(NSString *)identifier {
    if (![self groupForIdentifier:identifier]) {
        return NO;
    }
    self.selectedGroupIdentifier = identifier;
    [self persist];
    return YES;
}

- (nullable NSString *)createGroupWithName:(NSString *)name error:(NSError **)error {
    NSString *validName = [self validGroupName:name excludingGroup:nil error:error];
    if (!validName) {
        return nil;
    }
    WatchlistGroup *group = [[WatchlistGroup alloc] init];
    group.identifier = NSUUID.UUID.UUIDString;
    group.name = validName;
    group.codes = @[];
    [self.mutableGroups addObject:group];
    self.selectedGroupIdentifier = group.identifier;
    [self persist];
    return group.identifier;
}

- (BOOL)renameGroup:(NSString *)identifier name:(NSString *)name error:(NSError **)error {
    WatchlistGroup *group = [self groupForIdentifier:identifier];
    if (!group || [identifier isEqualToString:WatchlistDefaultGroupIdentifier]) {
        return NO;
    }
    NSString *validName = [self validGroupName:name excludingGroup:identifier error:error];
    if (!validName) {
        return NO;
    }
    group.name = validName;
    [self persist];
    return YES;
}

- (BOOL)removeGroup:(NSString *)identifier {
    WatchlistGroup *group = [self groupForIdentifier:identifier];
    if (!group || [identifier isEqualToString:WatchlistDefaultGroupIdentifier]) {
        return NO;
    }
    [self.mutableGroups removeObject:group];
    if ([self.selectedGroupIdentifier isEqualToString:identifier]) {
        self.selectedGroupIdentifier = WatchlistDefaultGroupIdentifier;
    }
    [self persist];
    return YES;
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
    NSCharacterSet *nonDigits = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet];
    if ([candidate rangeOfCharacterFromSet:nonDigits].location != NSNotFound) {
        return nil;
    }

    unichar first = [candidate characterAtIndex:0];
    BOOL isFund = [self isExchangeTradedFundCode:candidate];
    if (!isFund && first != '0' && first != '3' && first != '4' && first != '6' && first != '8' && first != '9') {
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
    if (first == '6' || first == '5') {
        market = @"sh";
    } else if (first == '0' || first == '3' || first == '1') {
        market = @"sz";
    } else {
        market = @"bj";
    }
    return [market stringByAppendingString:normalized];
}

+ (BOOL)isExchangeTradedFundCode:(NSString *)code {
    if (code.length != 6
        || [code rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789"] invertedSet]].location != NSNotFound) {
        return NO;
    }
    // Exchange-listed fund code ranges. Existence is verified by the quote
    // provider before adding; ordinary off-exchange fund codes stay unsupported.
    return [code hasPrefix:@"5"] || [code hasPrefix:@"15"]
        || [code hasPrefix:@"16"] || [code hasPrefix:@"18"];
}

- (BOOL)containsCode:(NSString *)code {
    NSString *normalized = [WatchlistStore normalizedCodeFromInput:code];
    return normalized && [self.codes containsObject:normalized];
}

- (BOOL)addCode:(NSString *)code {
    return [self addCode:code toGroup:self.selectedGroupIdentifier];
}

- (BOOL)addCode:(NSString *)code toGroup:(NSString *)identifier {
    NSString *normalized = [WatchlistStore normalizedCodeFromInput:code];
    WatchlistGroup *group = [self groupForIdentifier:identifier];
    if (!normalized || !group || [group.codes containsObject:normalized]) {
        return NO;
    }
    group.codes = [group.codes arrayByAddingObject:normalized];
    [self persist];
    return YES;
}

- (BOOL)removeCode:(NSString *)code {
    NSString *normalized = [WatchlistStore normalizedCodeFromInput:code];
    if (!normalized || ![self.codes containsObject:normalized]) {
        return NO;
    }
    NSMutableArray *codes = [self.codes mutableCopy];
    [codes removeObject:normalized];
    [self groupForIdentifier:self.selectedGroupIdentifier].codes = codes;
    [self persist];
    return YES;
}

- (BOOL)moveCode:(NSString *)code byOffset:(NSInteger)offset {
    NSString *normalized = [WatchlistStore normalizedCodeFromInput:code];
    if (!normalized || offset == 0) {
        return NO;
    }

    NSUInteger currentIndex = [self.codes indexOfObject:normalized];
    if (currentIndex == NSNotFound) {
        return NO;
    }

    NSInteger destination = (NSInteger)currentIndex + offset;
    if (destination < 0 || destination >= (NSInteger)self.codes.count) {
        return NO;
    }

    return [self moveCode:normalized toIndex:(NSUInteger)destination];
}

- (BOOL)moveCode:(NSString *)code toIndex:(NSUInteger)index {
    NSString *normalized = [WatchlistStore normalizedCodeFromInput:code];
    if (!normalized || index >= self.codes.count) {
        return NO;
    }

    NSUInteger currentIndex = [self.codes indexOfObject:normalized];
    if (currentIndex == NSNotFound || currentIndex == index) {
        return NO;
    }

    NSMutableArray *codes = [self.codes mutableCopy];
    [codes removeObjectAtIndex:currentIndex];
    [codes insertObject:normalized atIndex:index];
    [self groupForIdentifier:self.selectedGroupIdentifier].codes = codes;
    [self persist];
    return YES;
}

- (void)persist {
    NSMutableArray *records = [NSMutableArray arrayWithCapacity:self.mutableGroups.count];
    for (WatchlistGroup *group in self.mutableGroups) {
        [records addObject:@{@"id": group.identifier, @"name": group.name, @"codes": group.codes}];
    }
    [self.defaults setObject:records forKey:WatchlistGroupsKey];
    [self.defaults setObject:self.selectedGroupIdentifier forKey:SelectedGroupKey];
    // Keep the old key as the default group's list for a safe downgrade.
    [self.defaults setObject:[self groupForIdentifier:WatchlistDefaultGroupIdentifier].codes forKey:WatchlistDefaultsKey];
}

@end
