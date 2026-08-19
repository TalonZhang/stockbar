#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WatchlistStore : NSObject

@property (nonatomic, copy, readonly) NSArray<NSString *> *codes;

+ (nullable NSString *)normalizedCodeFromInput:(NSString *)input;
+ (nullable NSString *)marketSymbolForCode:(NSString *)code;

- (BOOL)containsCode:(NSString *)code;
- (BOOL)addCode:(NSString *)code;
- (BOOL)removeCode:(NSString *)code;
- (BOOL)moveCode:(NSString *)code byOffset:(NSInteger)offset;
- (BOOL)moveCode:(NSString *)code toIndex:(NSUInteger)index;

@end

NS_ASSUME_NONNULL_END
