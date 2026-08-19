#import <AppKit/AppKit.h>

@class StockQuote;
@class StockMenuItemView;

NS_ASSUME_NONNULL_BEGIN

@protocol StockMenuItemViewDelegate <NSObject>

- (void)stockMenuItemViewDidBeginDragging:(StockMenuItemView *)view;
- (void)stockMenuItemView:(StockMenuItemView *)view draggedToScreenPoint:(NSPoint)point;
- (void)stockMenuItemViewDidEndDragging:(StockMenuItemView *)view;
- (void)stockMenuItemViewDidRequestDelete:(StockMenuItemView *)view;

@end

@interface StockMenuItemView : NSView

@property (nonatomic, weak, nullable) id<StockMenuItemViewDelegate> delegate;
@property (nonatomic, copy, readonly) NSString *stockCode;
@property (nonatomic, getter=isDraggable) BOOL draggable;
@property (nonatomic, getter=isDeletable) BOOL deletable;
@property (nonatomic, getter=isDropTarget) BOOL dropTarget;

- (instancetype)initWithQuote:(StockQuote *)quote;
- (void)updateWithQuote:(StockQuote *)quote;

@end
NS_ASSUME_NONNULL_END
