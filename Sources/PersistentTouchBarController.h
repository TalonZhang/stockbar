#import <AppKit/AppKit.h>

@class StockQuote;

NS_ASSUME_NONNULL_BEGIN

@interface PersistentTouchBarController : NSObject <NSTouchBarDelegate>

@property (nonatomic, readonly, getter=isAvailable) BOOL available;
@property (nonatomic, readonly, getter=isPresented) BOOL presented;
@property (nonatomic, readonly, copy) NSString *diagnosticText;
@property (nonatomic) BOOL trayItemVisible;
@property (nonatomic) BOOL wantsPersistentPresentation;

- (void)updateQuotes:(NSArray<StockQuote *> *)quotes;
- (BOOL)present;
- (void)dismiss;
- (void)restoreIfNeeded;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
