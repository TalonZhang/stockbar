#import <AppKit/AppKit.h>

@class AddStockMenuItemView;

NS_ASSUME_NONNULL_BEGIN

@protocol AddStockMenuItemViewDelegate <NSObject>

- (void)addStockMenuItemView:(AddStockMenuItemView *)view didSubmitInput:(NSString *)input;

@end

@interface AddStockMenuItemView : NSView

@property (nonatomic, weak, nullable) id<AddStockMenuItemViewDelegate> delegate;

- (void)setValidating:(BOOL)validating;
- (void)clearInput;
- (void)focusAndSelectInput;

@end
NS_ASSUME_NONNULL_END
