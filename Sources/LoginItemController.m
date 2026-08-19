#import "LoginItemController.h"

#import <dlfcn.h>
#import <objc/message.h>

typedef id (*SendNoArgumentObjectFn)(id receiver, SEL selector);
typedef NSInteger (*SendNoArgumentIntegerFn)(id receiver, SEL selector);
typedef BOOL (*SendErrorFn)(id receiver, SEL selector, NSError **error);
typedef void (*SendNoArgumentVoidFn)(id receiver, SEL selector);

static NSString * const TSRegisteredLoginItemPathKey = @"loginitem.registered.bundle.path";

@interface LoginItemController ()

@property (nonatomic) BOOL available;
@property (nonatomic) BOOL enabled;
@property (nonatomic) BOOL requiresApproval;
@property (nonatomic, copy) NSString *statusText;
@property (nonatomic, strong, nullable) id service;
@property (nonatomic) Class serviceClass;
@property (nonatomic) SEL statusSelector;
@property (nonatomic) SEL registerSelector;
@property (nonatomic) SEL unregisterSelector;

@end

@implementation LoginItemController

- (instancetype)init {
    self = [super init];
    if (self) {
        _statusText = @"开机启动不可用";
        [self loadServiceManagement];
    }
    return self;
}

- (void)loadServiceManagement {
    void *framework = dlopen("/System/Library/Frameworks/ServiceManagement.framework/ServiceManagement", RTLD_LAZY | RTLD_LOCAL);
    if (!framework) {
        return;
    }

    self.serviceClass = NSClassFromString(@"SMAppService");
    SEL mainAppSelector = NSSelectorFromString(@"mainAppService");
    self.statusSelector = NSSelectorFromString(@"status");
    self.registerSelector = NSSelectorFromString(@"registerAndReturnError:");
    self.unregisterSelector = NSSelectorFromString(@"unregisterAndReturnError:");

    if (!self.serviceClass
        || ![self.serviceClass respondsToSelector:mainAppSelector]) {
        return;
    }

    SendNoArgumentObjectFn getMainAppService = (SendNoArgumentObjectFn)objc_msgSend;
    self.service = getMainAppService(self.serviceClass, mainAppSelector);
    self.available = self.service
        && [self.service respondsToSelector:self.statusSelector]
        && [self.service respondsToSelector:self.registerSelector]
        && [self.service respondsToSelector:self.unregisterSelector];
    [self refreshStatus];
}

- (void)refreshStatus {
    if (!self.available) {
        self.enabled = NO;
        self.requiresApproval = NO;
        self.statusText = @"当前系统不支持开机启动开关";
        return;
    }

    SendNoArgumentIntegerFn getStatus = (SendNoArgumentIntegerFn)objc_msgSend;
    NSInteger status = getStatus(self.service, self.statusSelector);
    self.enabled = status == 1 || status == 2;
    self.requiresApproval = status == 2;

    switch (status) {
        case 1:
            self.statusText = @"开机启动已启用";
            break;
        case 2:
            self.statusText = @"开机启动等待系统批准";
            break;
        case 3:
            self.statusText = @"系统未找到登录项";
            break;
        default:
            self.statusText = @"开机启动已关闭";
            break;
    }
}

- (BOOL)setEnabled:(BOOL)enabled error:(NSError **)error {
    if (!self.available) {
        if (error) {
            *error = [NSError errorWithDomain:@"dev.touchbarstocks.loginitem"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"当前系统不支持 SMAppService 登录项。"}];
        }
        return NO;
    }

    NSError *operationError = nil;
    SEL selector = enabled ? self.registerSelector : self.unregisterSelector;
    SendErrorFn operation = (SendErrorFn)objc_msgSend;
    BOOL succeeded = operation(self.service, selector, &operationError);
    [self refreshStatus];

    if (!succeeded) {
        BOOL alreadyInDesiredState = enabled ? self.enabled : !self.enabled;
        if (alreadyInDesiredState) {
            [self rememberRegistrationPathWhenEnabled:enabled];
            return YES;
        }
        if (error) {
            *error = operationError;
        }
        return NO;
    }
    [self rememberRegistrationPathWhenEnabled:enabled];
    return YES;
}

- (BOOL)repairRegistrationIfNeededWithError:(NSError **)error {
    [self refreshStatus];
    if (!self.available || !self.enabled) {
        return YES;
    }

    NSString *currentPath = NSBundle.mainBundle.bundlePath.stringByStandardizingPath;
    NSString *registeredPath = [[NSUserDefaults standardUserDefaults] stringForKey:TSRegisteredLoginItemPathKey];
    if ([registeredPath isEqualToString:currentPath]) {
        return YES;
    }

    SendErrorFn operation = (SendErrorFn)objc_msgSend;
    NSError *ignoredError = nil;
    operation(self.service, self.unregisterSelector, &ignoredError);

    NSError *registrationError = nil;
    BOOL registered = operation(self.service, self.registerSelector, &registrationError);
    [self refreshStatus];
    if (!registered && !self.enabled) {
        if (error) {
            *error = registrationError;
        }
        return NO;
    }

    [self rememberRegistrationPathWhenEnabled:YES];
    return YES;
}

- (void)rememberRegistrationPathWhenEnabled:(BOOL)enabled {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if (enabled) {
        [defaults setObject:NSBundle.mainBundle.bundlePath.stringByStandardizingPath
                     forKey:TSRegisteredLoginItemPathKey];
    } else {
        [defaults removeObjectForKey:TSRegisteredLoginItemPathKey];
    }
}

- (void)openSystemSettings {
    SEL selector = NSSelectorFromString(@"openSystemSettingsLoginItems");
    if ([self.serviceClass respondsToSelector:selector]) {
        SendNoArgumentVoidFn openSettings = (SendNoArgumentVoidFn)objc_msgSend;
        openSettings(self.serviceClass, selector);
    }
}

@end
