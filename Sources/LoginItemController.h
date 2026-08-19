#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LoginItemController : NSObject

@property (nonatomic, readonly, getter=isAvailable) BOOL available;
@property (nonatomic, readonly, getter=isEnabled) BOOL enabled;
@property (nonatomic, readonly) BOOL requiresApproval;
@property (nonatomic, copy, readonly) NSString *statusText;

- (void)refreshStatus;
- (BOOL)setEnabled:(BOOL)enabled error:(NSError *_Nullable *_Nullable)error;
- (BOOL)repairRegistrationIfNeededWithError:(NSError *_Nullable *_Nullable)error;
- (void)openSystemSettings;

@end

NS_ASSUME_NONNULL_END
