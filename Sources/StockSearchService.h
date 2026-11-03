#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSUInteger const StockSearchResultLimit;

@interface StockSearchResult : NSObject
@property (nonatomic, copy, readonly) NSString *code;
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *marketLabel;
- (instancetype)initWithCode:(NSString *)code name:(NSString *)name;
@end

typedef void (^StockSearchCompletion)(NSArray<StockSearchResult *> *results, NSError *_Nullable error);

@interface StockSearchService : NSObject
- (void)searchQuery:(NSString *)query completion:(StockSearchCompletion)completion;
- (void)cancel;
@end

NS_ASSUME_NONNULL_END
