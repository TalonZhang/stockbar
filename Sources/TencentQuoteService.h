#import <Foundation/Foundation.h>

@class StockQuote;

NS_ASSUME_NONNULL_BEGIN

typedef void (^QuoteServiceUpdateHandler)(NSArray<StockQuote *> *quotes, NSString *statusText);
typedef void (^QuoteValidationHandler)(StockQuote *_Nullable quote, NSError *_Nullable error);

FOUNDATION_EXPORT NSString * const QuoteCodeSSECompositeIndex;

typedef NS_ENUM(NSInteger, QuoteSource) {
    QuoteSourceAutomatic = 0,
    QuoteSourceTencent = 1,
    QuoteSourceEastmoney = 2
};

@interface TencentQuoteService : NSObject

@property (nonatomic, copy, nullable) QuoteServiceUpdateHandler updateHandler;
@property (nonatomic, copy, readonly) NSArray<NSString *> *codes;
@property (nonatomic) QuoteSource source;

+ (NSString *)displayNameForSource:(QuoteSource)source;

- (instancetype)initWithCodes:(NSArray<NSString *> *)codes NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

- (void)setCodes:(NSArray<NSString *> *)codes;
- (void)start;
- (void)stop;
- (void)refresh;
- (void)validateCode:(NSString *)code completion:(QuoteValidationHandler)completion;

@end

NS_ASSUME_NONNULL_END
