// (c) 2017-2024 Ricci Adams
// Modified for Apple Silicon and reliability improvements by Masahiro Fujimoto
// MIT License (or) 1-clause BSD License

#import <Foundation/Foundation.h>


@interface RestlessEngine : NSObject

- (NSArray<NSNumber *> *) pidsPreventingIdleSleep;

// Maps bundleIdentifier -> array of human-readable active assertion descriptions
// (e.g. "NoIdleSleepAssertion: Electron") for processes preventing idle/system sleep.
- (NSDictionary<NSString *, NSArray<NSString *> *> *) idleSleepAssertionsByBundleIdentifier;

- (void) checkHelper;

- (void) preventLidCloseSleep;
- (void) allowLidCloseSleepAfter:(NSTimeInterval)delay;

// For application termination (callback is guaranteed to be called once on the main thread)
- (void) allowLidCloseSleepWithCallback:(void (^)(void))callback;

@property (nonatomic, readonly, getter=isPreventingLidCloseSleep) BOOL preventingLidCloseSleep;
@property (nonatomic, readonly, getter=isHelperAvailable) BOOL helperAvailable;

@property (nonatomic) BOOL alsoPreventDisplaySleep;

// When YES (default), closing the lid while Fermata is preventing sleep turns the
// built-in display off (system and apps keep running). Skipped when an external
// display is in use (clamshell mode). The display wakes normally when the lid opens.
@property (nonatomic) BOOL sleepDisplayOnLidClose;

@property (nonatomic, readonly, getter=isLidClosed) BOOL lidClosed;

@end
