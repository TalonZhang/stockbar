#import <Foundation/Foundation.h>
#import "WatchlistGroup.h"

NS_ASSUME_NONNULL_BEGIN

@interface WatchlistStore : NSObject

@property (nonatomic, copy, readonly) NSArray<NSString *> *codes;
@property (nonatomic, copy, readonly) NSArray<NSString *> *allCodes;
@property (nonatomic, copy, readonly) NSArray<WatchlistGroup *> *groups;
@property (nonatomic, copy, readonly) NSString *selectedGroupIdentifier;
@property (nonatomic, copy, readonly) NSString *selectedGroupName;

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
+ (NSString *)displayNameForGroupName:(NSString *)name;
- (BOOL)selectGroup:(NSString *)identifier;
- (nullable NSString *)createGroupWithName:(NSString *)name error:(NSError *_Nullable *_Nullable)error;
- (BOOL)renameGroup:(NSString *)identifier name:(NSString *)name error:(NSError *_Nullable *_Nullable)error;
- (BOOL)removeGroup:(NSString *)identifier;

+ (nullable NSString *)normalizedCodeFromInput:(NSString *)input;
+ (nullable NSString *)marketSymbolForCode:(NSString *)code;
+ (BOOL)isExchangeTradedFundCode:(NSString *)code;

- (BOOL)containsCode:(NSString *)code;
- (BOOL)addCode:(NSString *)code;
- (BOOL)addCode:(NSString *)code toGroup:(NSString *)identifier;
- (BOOL)removeCode:(NSString *)code;
- (BOOL)moveCode:(NSString *)code byOffset:(NSInteger)offset;
- (BOOL)moveCode:(NSString *)code toIndex:(NSUInteger)index;

@end

NS_ASSUME_NONNULL_END
