#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface StockQuote : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *code;
@property (nonatomic) double previousClose;
@property (nonatomic) double price;
@property (nonatomic) double percentChange;
@property (nonatomic, getter=isAvailable) BOOL available;
@property (nonatomic, strong) NSDate *updatedAt;
@property (nonatomic, copy, readonly) NSString *formattedPrice;

- (instancetype)initWithName:(NSString *)name
                         code:(NSString *)code
                previousClose:(double)previousClose
                       price:(double)price NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
