#import <AppKit/AppKit.h>
#import "StockSearchService.h"

NS_ASSUME_NONNULL_BEGIN

@class StockSearchWindowController;
typedef void (^SearchAddCompletion)(NSError *_Nullable error);

@protocol StockSearchWindowControllerDelegate <NSObject>
- (void)stockSearchController:(StockSearchWindowController *)controller
             didChooseResult:(StockSearchResult *)result
             groupIdentifier:(NSString *)groupIdentifier
                  completion:(SearchAddCompletion)completion;
@end

@interface StockSearchWindowController : NSWindowController
@property (nonatomic, weak, nullable) id<StockSearchWindowControllerDelegate> delegate;
- (void)showQuery:(NSString *)query groupIdentifier:(NSString *)groupIdentifier
       groupName:(NSString *)groupName anchorRect:(NSRect)anchor;
- (void)showQuery:(NSString *)query groupIdentifier:(NSString *)groupIdentifier
       groupName:(NSString *)groupName anchorRect:(NSRect)anchor submitImmediately:(BOOL)submit;
@end

NS_ASSUME_NONNULL_END
