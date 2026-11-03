#import <AppKit/AppKit.h>
#import "WatchlistGroup.h"

NS_ASSUME_NONNULL_BEGIN

@class GroupTabsMenuItemView;

@protocol GroupTabsMenuItemViewDelegate <NSObject>
- (void)groupTabsView:(GroupTabsMenuItemView *)view didSelectGroup:(NSString *)identifier;
- (void)groupTabsViewDidRequestCreate:(GroupTabsMenuItemView *)view;
- (void)groupTabsViewDidRequestManagement:(GroupTabsMenuItemView *)view;
@end

@interface GroupTabsMenuItemView : NSView
@property (nonatomic, weak, nullable) id<GroupTabsMenuItemViewDelegate> delegate;
- (void)updateGroups:(NSArray<WatchlistGroup *> *)groups selectedIdentifier:(NSString *)identifier;
- (void)showManagementMenu:(NSMenu *)menu;
@end

NS_ASSUME_NONNULL_END
