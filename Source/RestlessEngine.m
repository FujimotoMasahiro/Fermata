// (c) 2017-2024 Ricci Adams
// Modified for Apple Silicon and reliability improvements by Masahiro Fujimoto
// MIT License (or) 1-clause BSD License

#import "RestlessEngine.h"

#import "Entry.h"
#import "AppleSPI.h"
#import "HelperProtocol.h"

@import ServiceManagement;
@import IOKit.pwr_mgt;
@import AppKit;
@import CoreGraphics;

#import <IOKit/pwr_mgt/IOPM.h>

static const NSTimeInterval kHelperCommandTimeoutSeconds = 3.0;
static const NSTimeInterval kTerminationTimeoutSeconds   = 2.5;

// Delay after the lid closes before turning the display off, so that macOS has
// finished reconfiguring displays (needed to detect external-display clamshell mode).
static const NSTimeInterval kLidCloseDisplaySleepDelay    = 1.5;

// While the lid stays closed, re-check periodically in case something woke the display.
static const NSTimeInterval kLidClosedWatchdogInterval    = 30.0;


@interface RestlessEngine ()
@property (nonatomic, getter=isPreventingLidCloseSleep) BOOL preventingLidCloseSleep;
@property (nonatomic, getter=isHelperAvailable) BOOL helperAvailable;
@property (nonatomic, getter=isLidClosed) BOOL lidClosed;
- (void) _handleLidClosed:(BOOL)closed;
@end


@implementation RestlessEngine {
    NSInteger _helperVersion;
    NSXPCConnection *_connection;

    IOPMAssertionID _displaySleepAssertion;
    IOPMAssertionID _idleSleepAssertion;

    IONotificationPortRef _clamshellNotifyPort;
    io_object_t _clamshellNotifier;
    NSTimer *_lidClosedWatchdog;
}


- (instancetype) init
{
    if ((self = [super init])) {
        _sleepDisplayOnLidClose = YES;
        [self _startClamshellMonitoring];
    }

    return self;
}


- (void) dealloc
{
    [self _stopClamshellMonitoring];
    [self _releaseAllAssertions];
    [_connection invalidate];
    _connection = nil;
}


#pragma mark - Private Methods

- (void) _releaseAllAssertions
{
    if (_displaySleepAssertion) {
        IOPMAssertionRelease(_displaySleepAssertion);
        _displaySleepAssertion = kIOPMNullAssertionID;
    }

    if (_idleSleepAssertion) {
        IOPMAssertionRelease(_idleSleepAssertion);
        _idleSleepAssertion = kIOPMNullAssertionID;
    }
}


- (BOOL) _attemptToBlessHelper
{
    AuthorizationItem   item   = { kSMRightBlessPrivilegedHelper, 0, NULL, 0 };
    AuthorizationRights rights = { 1, &item };
    AuthorizationFlags  flags  = kAuthorizationFlagDefaults           |
                                 kAuthorizationFlagInteractionAllowed |
                                 kAuthorizationFlagPreAuthorize       |
                                 kAuthorizationFlagExtendRights;

    AuthorizationRef authRef = NULL;

    OSStatus status = AuthorizationCreate(&rights, kAuthorizationEmptyEnvironment, flags, &authRef);

    if (status != errAuthorizationSuccess) {
        NSLog(@"AuthorizationCreate failed: %ld", (long)status);
        return NO;
    }

    CFErrorRef cfError = NULL;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    BOOL result = SMJobBless(kSMDomainSystemLaunchd, (__bridge CFStringRef)kHelperMachServiceName, authRef, &cfError);
#pragma clang diagnostic pop

    AuthorizationFree(authRef, kAuthorizationFlagDefaults);

    if (!result || cfError) {
        NSError *error = CFBridgingRelease(cfError);
        NSLog(@"SMJobBless returned %ld: %@ (If using an ad-hoc/unsigned build, run Scripts/install-helper.sh)", (long)result, error);
        return NO;
    }

    return YES;
}


- (NSXPCConnection *) _helperConnection
{
    if (!_connection) {
        NSXPCConnection *conn = [[NSXPCConnection alloc] initWithMachServiceName:kHelperMachServiceName
                                                                         options:NSXPCConnectionPrivileged];
        [conn setRemoteObjectInterface:[NSXPCInterface interfaceWithProtocol:@protocol(HelperProtocol)]];

        __weak typeof(self) weakSelf = self;
        [conn setInterruptionHandler:^{
            NSLog(@"Fermata helper XPC connection interrupted.");
        }];

        [conn setInvalidationHandler:^{
            NSLog(@"Fermata helper XPC connection invalidated.");
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(self) strongSelf = weakSelf;
                if (strongSelf && strongSelf->_connection == conn) {
                    strongSelf->_connection = nil;
                }
            });
        }];

        [conn resume];
        _connection = conn;
    }

    return _connection;
}


- (void) _launchHelperWithCommand:(NSString *)command
                          timeout:(NSTimeInterval)timeoutSeconds
                            reply:(void (^)(BOOL success, NSInteger value))reply
{
    NSXPCConnection *connection = [self _helperConnection];

    __block BOOL completed = NO;
    NSLock *lock = [[NSLock alloc] init];

    __weak typeof(self) weakSelf = self;

    void (^finish)(BOOL, NSInteger) = ^(BOOL success, NSInteger value) {
        [lock lock];
        if (completed) {
            [lock unlock];
            return;
        }
        completed = YES;
        [lock unlock];

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(self) strongSelf = weakSelf;
            if (strongSelf) {
                if (success) {
                    strongSelf.helperAvailable = YES;
                }
                [strongSelf _checkStatus];
            }
            if (reply) reply(success, value);
        });
    };

    if (timeoutSeconds > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeoutSeconds * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            finish(NO, -1);
        });
    }

    id<HelperProtocol> proxy = [connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
        NSLog(@"Couldn't communicate with helper (%@): %@", command, error);
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(self) strongSelf = weakSelf;
            if (strongSelf) {
                [strongSelf->_connection invalidate];
                strongSelf->_connection = nil;
                strongSelf.helperAvailable = NO;
            }
        });
        finish(NO, -1);
    }];

    void (^wrappedReply)(NSInteger) = ^(NSInteger arg) {
        finish(YES, arg);
    };

    if ([command isEqualToString:@"prevent"]) {
        [proxy preventSleepWithReply:wrappedReply];
    } else if ([command isEqualToString:@"allow"]) {
        [proxy allowSleepWithReply:wrappedReply];
    } else if ([command isEqualToString:@"version"]) {
        [proxy requestVersionWithReply:wrappedReply];
    } else {
        finish(NO, -1);
    }
}


- (void) _allowLidCloseSleep
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_allowLidCloseSleep) object:nil];
    [self _launchHelperWithCommand:@"allow" timeout:kHelperCommandTimeoutSeconds reply:nil];
}


- (void) _checkStatus
{
    NSDictionary *dictionary = CFBridgingRelease(IOPMCopySystemPowerSettings());

    BOOL isPreventingLidCloseSleep = [[dictionary objectForKey:(__bridge id)kIOPMSleepDisabledKey] boolValue];
    [self setPreventingLidCloseSleep:isPreventingLidCloseSleep];
}


- (void) _didReceiveHelperVersion:(NSInteger)version
{
    _helperVersion = version;
    self.helperAvailable = (version == kHelperVersion);
    [[NSUserDefaults standardUserDefaults] setInteger:version forKey:@"HelperVersion"];

    if (_helperVersion != kHelperVersion) {
        [self _tryBlessAndVerify];
    }
}


- (void) _tryBlessAndVerify
{
    if (![self _attemptToBlessHelper]) {
        _helperVersion = 0;
        self.helperAvailable = NO;
        return;
    }

    __weak typeof(self) weakSelf = self;
    [self _launchHelperWithCommand:@"version" timeout:kHelperCommandTimeoutSeconds reply:^(BOOL success, NSInteger version) {
        __strong typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;

        if (success && version == kHelperVersion) {
            strongSelf->_helperVersion = version;
            strongSelf.helperAvailable = YES;
            [[NSUserDefaults standardUserDefaults] setInteger:version forKey:@"HelperVersion"];
        } else {
            strongSelf->_helperVersion = 0;
            strongSelf.helperAvailable = NO;
        }
    }];
}


- (void) _updateAssertion:(IOPMAssertionID *)assertionPtr type:(CFStringRef)type enabled:(BOOL)enabled
{
    if (enabled && (*assertionPtr == 0)) {
        IOPMAssertionCreateWithName(type, kIOPMAssertionLevelOn, CFSTR("Fermata is active"), assertionPtr);
    } else if (!enabled && *assertionPtr) {
        IOPMAssertionRelease(*assertionPtr);
        *assertionPtr = kIOPMNullAssertionID;
    }
}


- (void) _updateAdditionalAssertions
{
    // Never hold the display awake behind a closed lid.
    BOOL shouldPreventDisplaySleep = _preventingLidCloseSleep && _alsoPreventDisplaySleep && !_lidClosed;

    [self _updateAssertion:&_displaySleepAssertion type:kIOPMAssertPreventUserIdleDisplaySleep enabled:shouldPreventDisplaySleep];
    [self _updateAssertion:&_idleSleepAssertion    type:kIOPMAssertPreventUserIdleSystemSleep  enabled:_preventingLidCloseSleep];
}


#pragma mark - Lid (Clamshell) Handling

static void sClamshellInterestCallback(void *refcon, io_service_t service, natural_t messageType, void *messageArgument)
{
    if (messageType != kIOPMMessageClamshellStateChange) return;

    BOOL closed = (((uintptr_t)messageArgument) & kClamshellStateBit) != 0;
    RestlessEngine *engine = (__bridge RestlessEngine *)refcon;

    dispatch_async(dispatch_get_main_queue(), ^{
        [engine _handleLidClosed:closed];
    });
}


- (void) _startClamshellMonitoring
{
    io_service_t rootDomain = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"));
    if (!rootDomain) {
        NSLog(@"Fermata: IOPMrootDomain not found; lid-close display sleep disabled.");
        return;
    }

    CFTypeRef state = IORegistryEntryCreateCFProperty(rootDomain, CFSTR(kAppleClamshellStateKey), kCFAllocatorDefault, 0);
    if (state) {
        _lidClosed = (CFGetTypeID(state) == CFBooleanGetTypeID()) && CFBooleanGetValue(state);
        CFRelease(state);
    }

    _clamshellNotifyPort = IONotificationPortCreate(kIOMainPortDefault);
    if (_clamshellNotifyPort) {
        IONotificationPortSetDispatchQueue(_clamshellNotifyPort, dispatch_get_main_queue());

        kern_return_t kr = IOServiceAddInterestNotification(_clamshellNotifyPort, rootDomain, kIOGeneralInterest,
                                                            sClamshellInterestCallback, (__bridge void *)self,
                                                            &_clamshellNotifier);
        if (kr != KERN_SUCCESS) {
            NSLog(@"Fermata: IOServiceAddInterestNotification failed: 0x%x", kr);
            _clamshellNotifier = IO_OBJECT_NULL;
        }
    }

    IOObjectRelease(rootDomain);
}


- (void) _stopClamshellMonitoring
{
    [_lidClosedWatchdog invalidate];
    _lidClosedWatchdog = nil;

    if (_clamshellNotifier) {
        IOObjectRelease(_clamshellNotifier);
        _clamshellNotifier = IO_OBJECT_NULL;
    }

    if (_clamshellNotifyPort) {
        IONotificationPortDestroy(_clamshellNotifyPort);
        _clamshellNotifyPort = NULL;
    }
}


- (void) _handleLidClosed:(BOOL)closed
{
    if (_lidClosed == closed) return;
    self.lidClosed = closed;

    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_sleepDisplayIfLidClosed) object:nil];
    [self _updateAdditionalAssertions];

    if (closed) {
        [self performSelector:@selector(_sleepDisplayIfLidClosed) withObject:nil afterDelay:kLidCloseDisplaySleepDelay];
        [self _updateLidClosedWatchdog];
    } else {
        [self _updateLidClosedWatchdog];

        // Make sure the display comes back right away on lid open.
        IOPMAssertionID activity = kIOPMNullAssertionID;
        IOPMAssertionDeclareUserActivity(CFSTR("Fermata: lid opened"), kIOPMUserActiveLocal, &activity);
        if (activity) IOPMAssertionRelease(activity);
    }
}


- (BOOL) _shouldSleepDisplayForClosedLid
{
    return _lidClosed && _preventingLidCloseSleep && _sleepDisplayOnLidClose;
}


- (BOOL) _isExternalDisplayActive
{
    uint32_t count = 0;
    CGDirectDisplayID displays[16];

    if (CGGetActiveDisplayList(16, displays, &count) != kCGErrorSuccess) {
        return YES; // Be conservative: never blank a screen we can't reason about.
    }

    for (uint32_t i = 0; i < count; i++) {
        if (!CGDisplayIsBuiltin(displays[i]) && !CGDisplayIsAsleep(displays[i])) {
            return YES;
        }
    }

    return NO;
}


- (BOOL) _isAnyDisplayAwake
{
    uint32_t count = 0;
    CGDirectDisplayID displays[16];

    if (CGGetOnlineDisplayList(16, displays, &count) != kCGErrorSuccess) return YES;

    for (uint32_t i = 0; i < count; i++) {
        if (!CGDisplayIsAsleep(displays[i])) return YES;
    }

    return NO;
}


- (void) _sleepDisplayNow
{
    // `pmset displaysleepnow` is the supported way to turn displays off immediately.
    // It needs no root privileges and does not put the system to sleep.
    @try {
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/pmset"];
        task.arguments = @[ @"displaysleepnow" ];
        task.standardOutput = [NSFileHandle fileHandleWithNullDevice];
        task.standardError  = [NSFileHandle fileHandleWithNullDevice];

        NSError *error = nil;
        if ([task launchAndReturnError:&error]) return;
        NSLog(@"Fermata: pmset displaysleepnow failed: %@", error);
    } @catch (NSException *exception) {
        NSLog(@"Fermata: pmset displaysleepnow raised: %@", exception);
    }

    // Fallback: ask IODisplayWrangler to go idle.
    io_service_t wrangler = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IODisplayWrangler"));
    if (wrangler) {
        IORegistryEntrySetCFProperty(wrangler, CFSTR("IORequestIdle"), kCFBooleanTrue);
        IOObjectRelease(wrangler);
    }
}


- (void) _sleepDisplayIfLidClosed
{
    if (![self _shouldSleepDisplayForClosedLid]) return;
    if ([self _isExternalDisplayActive]) return;   // Clamshell mode with an external monitor: leave it alone.
    if (![self _isAnyDisplayAwake]) return;

    [self _sleepDisplayNow];
}


- (void) _updateLidClosedWatchdog
{
    BOOL shouldRun = [self _shouldSleepDisplayForClosedLid];

    if (shouldRun && !_lidClosedWatchdog) {
        __weak typeof(self) weakSelf = self;
        _lidClosedWatchdog = [NSTimer scheduledTimerWithTimeInterval:kLidClosedWatchdogInterval repeats:YES block:^(NSTimer *timer) {
            [weakSelf _sleepDisplayIfLidClosed];
        }];
        _lidClosedWatchdog.tolerance = 5.0;

    } else if (!shouldRun && _lidClosedWatchdog) {
        [_lidClosedWatchdog invalidate];
        _lidClosedWatchdog = nil;
    }
}



#pragma mark - Public Methods

- (void) checkHelper
{
    __weak typeof(self) weakSelf = self;

    // First try talking to an already-installed helper (supports both SMJobBless and manual install-helper.sh).
    [self _launchHelperWithCommand:@"version" timeout:kHelperCommandTimeoutSeconds reply:^(BOOL success, NSInteger version) {
        __strong typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;

        if (success && version == kHelperVersion) {
            [strongSelf _didReceiveHelperVersion:version];
        } else {
            // Helper missing or outdated; attempt SMJobBless (works on Developer ID signed builds).
            [strongSelf _tryBlessAndVerify];
        }
    }];
}


- (NSArray<NSNumber *> *) pidsPreventingIdleSleep
{
    NSMutableArray *result = [NSMutableArray array];

    CFDictionaryRef cfAssertionsMap = NULL;
    IOReturn err = IOPMCopyAssertionsByProcess(&cfAssertionsMap);

    if (!err && cfAssertionsMap) {
        NSDictionary *assertionsMap = (__bridge id)cfAssertionsMap;
        for (NSNumber *pidNumber in assertionsMap) {
            NSArray *assertions = [assertionsMap objectForKey:pidNumber];

            for (NSDictionary *dictionary in assertions) {
                NSString *assertionType = [dictionary objectForKey:(__bridge id)kIOPMAssertionTypeKey];

                if ([assertionType isEqualToString:(__bridge id)kIOPMAssertPreventUserIdleSystemSleep] ||
                    [assertionType isEqualToString:(__bridge id)kIOPMAssertionTypeNoIdleSleep] ||
                    [assertionType isEqualToString:(__bridge id)kIOPMAssertionTypePreventSystemSleep]
                ) {
                    [result addObject:pidNumber];
                }
            }
        }
    }

    if (cfAssertionsMap) CFRelease(cfAssertionsMap);

    return result;
}


- (NSDictionary<NSString *, NSArray<NSString *> *> *) idleSleepAssertionsByBundleIdentifier
{
    NSMutableDictionary<NSString *, NSMutableArray<NSString *> *> *byBundleID = [NSMutableDictionary dictionary];

    CFDictionaryRef cfAssertionsMap = NULL;
    IOReturn err = IOPMCopyAssertionsByProcess(&cfAssertionsMap);

    if (!err && cfAssertionsMap) {
        NSDictionary *assertionsMap = (__bridge id)cfAssertionsMap;
        for (NSNumber *pidNumber in assertionsMap) {
            pid_t pid = (pid_t)[pidNumber integerValue];
            NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
            NSString *bundleID = app.bundleIdentifier;
            if (!bundleID) continue;

            NSArray *assertions = [assertionsMap objectForKey:pidNumber];
            for (NSDictionary *dictionary in assertions) {
                NSString *assertionType = [dictionary objectForKey:(__bridge id)kIOPMAssertionTypeKey];

                if ([assertionType isEqualToString:(__bridge id)kIOPMAssertPreventUserIdleSystemSleep] ||
                    [assertionType isEqualToString:(__bridge id)kIOPMAssertionTypeNoIdleSleep] ||
                    [assertionType isEqualToString:(__bridge id)kIOPMAssertionTypePreventSystemSleep]
                ) {
                    NSString *assertionName = [dictionary objectForKey:(__bridge id)kIOPMAssertionNameKey];
                    NSString *desc = assertionName.length > 0
                        ? [NSString stringWithFormat:@"%@: %@", assertionType, assertionName]
                        : assertionType;

                    NSMutableArray<NSString *> *list = byBundleID[bundleID];
                    if (!list) {
                        list = [NSMutableArray array];
                        byBundleID[bundleID] = list;
                    }
                    if (![list containsObject:desc]) {
                        [list addObject:desc];
                    }
                }
            }
        }
    }

    if (cfAssertionsMap) CFRelease(cfAssertionsMap);

    return byBundleID;
}


- (void) allowLidCloseSleepWithCallback:(void (^)(void))callback
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_allowLidCloseSleep) object:nil];
    [self _releaseAllAssertions];

    __weak typeof(self) weakSelf = self;
    [self _launchHelperWithCommand:@"allow" timeout:kTerminationTimeoutSeconds reply:^(BOOL success, NSInteger value) {
        __strong typeof(self) strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf->_connection invalidate];
            strongSelf->_connection = nil;
        }
        if (callback) callback();
    }];
}


- (void) preventLidCloseSleep
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(_allowLidCloseSleep) object:nil];
    [self _launchHelperWithCommand:@"prevent" timeout:kHelperCommandTimeoutSeconds reply:nil];
}


- (void) allowLidCloseSleepAfter:(NSTimeInterval)delay
{
    [self performSelector:@selector(_allowLidCloseSleep) withObject:nil afterDelay:delay];
}


#pragma mark - Accessors

- (void) setPreventingLidCloseSleep:(BOOL)preventingLidCloseSleep
{
    if (_preventingLidCloseSleep != preventingLidCloseSleep) {
        _preventingLidCloseSleep = preventingLidCloseSleep;
        [self _updateAdditionalAssertions];
        [self _updateLidClosedWatchdog];

        if (preventingLidCloseSleep && _lidClosed) {
            [self performSelector:@selector(_sleepDisplayIfLidClosed) withObject:nil afterDelay:kLidCloseDisplaySleepDelay];
        }
    }
}


- (void) setSleepDisplayOnLidClose:(BOOL)sleepDisplayOnLidClose
{
    if (_sleepDisplayOnLidClose != sleepDisplayOnLidClose) {
        _sleepDisplayOnLidClose = sleepDisplayOnLidClose;
        [self _updateLidClosedWatchdog];
    }
}


- (void) setAlsoPreventDisplaySleep:(BOOL)alsoPreventDisplaySleep
{
    if (_alsoPreventDisplaySleep != alsoPreventDisplaySleep) {
        _alsoPreventDisplaySleep = alsoPreventDisplaySleep;
        [self _updateAdditionalAssertions];
    }
}


@end
