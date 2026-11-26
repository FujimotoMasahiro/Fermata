// (c) 2017-2024 Ricci Adams
// Modified for Apple Silicon and reliability improvements by Masahiro Fujimoto
// MIT License (or) 1-clause BSD License

#import "AppDelegate.h"
#import "RestlessEngine.h"
#import "PreferencesController.h"
#import "Entry.h"
#import "Localization.h"


@import ServiceManagement;

static NSString * const LaunchAtLoginPreferenceKey        = @"LaunchAtLogin";
static NSString * const RestlessApplicationsPreferenceKey = @"RestlessApplications";
static NSString * const ManualPreventionKey               = @"ManualPrevention";
static NSString * const ManualDurationKey                 = @"ManualDuration";
static NSString * const UpdateFrequencyKey                = @"UpdateFrequency";
static NSString * const ReenableDelayKey                  = @"ReenableDelay";
static NSString * const AlsoPreventDisplaySleepKey        = @"AlsoPreventDisplaySleep";
static NSString * const SleepDisplayOnLidCloseKey         = @"SleepDisplayOnLidClose";

static NSString * const kFermataUpdateNotificationName    = @"com.fujimotomasahiro.Fermata.Update";
static NSString * const kFermataLauncherBundleID          = @"com.fujimotomasahiro.Fermata.Launcher";


@interface AppDelegate () <NSMenuDelegate>

@property (weak) IBOutlet NSMenu *statusItemMenu;
@property (weak) IBOutlet NSMenuItem *lidCloseMenuItem;
@property (weak) IBOutlet NSMenuItem *settingsMenuItem;
@property (weak) IBOutlet NSMenuItem *aboutMenuItem;
@property (weak) IBOutlet NSMenuItem *quitMenuItem;

@end


@implementation AppDelegate {
    NSStatusItem   *_statusItem;
    NSImage *_onImage;
    NSImage *_offImage;

    RestlessEngine *_engine;
    PreferencesController *_preferencesController;
    NSTimer *_timer;

    BOOL _applicationIsTerminating;

    BOOL _manualPreventionActive;
    NSTimeInterval _manualPreventionStartTime;
    NSTimer *_manualPreventionTimer;

    NSArrayController *_entryArrayController;
    NSMenuItem *_statusMenuItem;
    NSString *_activeTriggerSummary;
}


- (void) applicationDidFinishLaunching:(NSNotification *)aNotification
{
    NSDictionary *defaults = @{
        LaunchAtLoginPreferenceKey: @NO,
        ManualPreventionKey: @NO,
        RestlessApplicationsPreferenceKey: @[],

        UpdateFrequencyKey: @10,
        ReenableDelayKey:   @10,
        ManualDurationKey:  @10,

        AlsoPreventDisplaySleepKey: @NO,
        SleepDisplayOnLidCloseKey:  @YES,

        FermataLanguagePreferenceKey: FermataLanguageValueSystem
    };

    [[NSUserDefaults standardUserDefaults] registerDefaults:defaults];

    _engine = [[RestlessEngine alloc] init];
    [_engine addObserver:self forKeyPath:@"preventingLidCloseSleep" options:0 context:NULL];

    [_engine checkHelper];

    _statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:30.0];

    _onImage  = [NSImage imageNamed:@"StatusItemIconOn"];
    _offImage = [NSImage imageNamed:@"StatusItemIconOff"];

    if (_statusItem.button) {
        _statusItem.button.image = _offImage;
    }
    self.statusItemMenu.delegate = self;
    _statusMenuItem = [[NSMenuItem alloc] initWithTitle:@"" action:nil keyEquivalent:@""];
    _statusMenuItem.enabled = NO;
    [self.statusItemMenu insertItem:_statusMenuItem atIndex:0];
    [self.statusItemMenu insertItem:[NSMenuItem separatorItem] atIndex:1];
    [_statusItem setMenu:[self statusItemMenu]];

    [self _applyLocalization];
    [self _updateTimer];

    [self _loadState];

    [self _updateEngineManually:YES];
    [self _updateLaunchHelper];

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_handleUserDefaultsDidChangeNotification:) name:NSUserDefaultsDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_handleEntryDidUpdateNotification:)        name:EntryDidUpdateNotification          object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_handleLanguageDidChangeNotification:)     name:FermataLanguageDidChangeNotification object:nil];

    [[NSDistributedNotificationCenter defaultCenter] addObserver: self
                                                        selector: @selector(_handleFermataUpdateNotification:)
                                                            name: kFermataUpdateNotificationName
                                                          object: nil
                                              suspensionBehavior: NSNotificationSuspensionBehaviorDeliverImmediately];

    [[NSWorkspace sharedWorkspace] addObserver:self forKeyPath:@"runningApplications" options:0 context:NULL];
}


- (NSApplicationTerminateReply) applicationShouldTerminate:(NSApplication *)sender
{
    _applicationIsTerminating = YES;

    [_timer invalidate];
    _timer = nil;

    [_manualPreventionTimer invalidate];
    _manualPreventionTimer = nil;

    [_engine allowLidCloseSleepWithCallback:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [[NSApplication sharedApplication] replyToApplicationShouldTerminate:YES];
        });
    }];

    return NSTerminateLater;
}


- (void) _applyLocalization
{
    if ([[NSUserDefaults standardUserDefaults] integerForKey:ManualDurationKey] > 0) {
        self.lidCloseMenuItem.title = FermataLocalizedString(@"menu.postpone");
    } else {
        self.lidCloseMenuItem.title = FermataLocalizedString(@"menu.prevent");
    }
    self.lidCloseMenuItem.toolTip = FermataLocalizedString(@"tooltip.menu.lid_close");

    self.settingsMenuItem.title   = FermataLocalizedString(@"menu.settings");
    self.settingsMenuItem.toolTip = FermataLocalizedString(@"tooltip.menu.settings");

    self.aboutMenuItem.title      = FermataLocalizedString(@"menu.about");
    self.aboutMenuItem.toolTip    = FermataLocalizedString(@"tooltip.menu.about");

    self.quitMenuItem.title       = FermataLocalizedString(@"menu.quit");
    self.quitMenuItem.toolTip     = FermataLocalizedString(@"tooltip.menu.quit");

    [self _updateStatusMenuItem];
}


- (void) _updateStatusMenuItem
{
    if (!_statusMenuItem) return;

    BOOL active = [_engine isPreventingLidCloseSleep];
    NSString *dot = active ? @"● " : @"○ ";
    NSColor *dotColor = active ? [NSColor systemGreenColor] : [NSColor tertiaryLabelColor];
    NSString *text = nil;

    if (active) {
        if (_activeTriggerSummary.length > 0) {
            text = [NSString stringWithFormat:FermataLocalizedString(@"menu.status.active_reason"), _activeTriggerSummary];
        } else {
            text = FermataLocalizedString(@"menu.status.active");
        }
    } else {
        text = FermataLocalizedString(@"menu.status.inactive");
    }

    NSMutableAttributedString *attr = [[NSMutableAttributedString alloc] init];
    [attr appendAttributedString:[[NSAttributedString alloc] initWithString:dot attributes:@{
        NSFontAttributeName: [NSFont menuFontOfSize:11.0],
        NSForegroundColorAttributeName: dotColor
    }]];
    [attr appendAttributedString:[[NSAttributedString alloc] initWithString:text attributes:@{
        NSFontAttributeName: [NSFont menuFontOfSize:12.0],
        NSForegroundColorAttributeName: [NSColor secondaryLabelColor]
    }]];

    _statusMenuItem.attributedTitle = attr;
}


- (void) menuWillOpen:(NSMenu *)menu
{
    if (menu == self.statusItemMenu) {
        [self _updateEngineManually:NO];
        [self _updateStatusMenuItem];
    }
}


- (BOOL) validateMenuItem:(NSMenuItem *)menuItem
{
    SEL action = [menuItem action];

    if (action == @selector(preventLidCloseSleep:)) {
        [menuItem setState:(_manualPreventionActive ? NSControlStateValueOn : NSControlStateValueOff)];

        if ([[NSUserDefaults standardUserDefaults] integerForKey:ManualDurationKey] > 0) {
            [menuItem setTitle:FermataLocalizedString(@"menu.postpone")];
        } else {
            [menuItem setTitle:FermataLocalizedString(@"menu.prevent")];
        }
    }

    return YES;
}


- (void) _updateTimer
{
    NSTimeInterval updateFrequency = [[NSUserDefaults standardUserDefaults] doubleForKey:UpdateFrequencyKey];
    if (updateFrequency < 1.0) {
        updateFrequency = 1.0;
    }

    if ([_timer timeInterval] != updateFrequency) {
        [_timer invalidate];

        __weak typeof(self) weakSelf = self;
        _timer = [NSTimer scheduledTimerWithTimeInterval:updateFrequency repeats:YES block:^(NSTimer *timer) {
            [weakSelf _updateEngineManually:NO];
        }];

        [_timer setTolerance:(updateFrequency < 2.0) ? 0.1 : 1.0];
    }
}



#pragma mark - Private Methods

- (void) _loadState
{
    NSUserDefaults *defaults     = [NSUserDefaults standardUserDefaults];
    NSArray        *dictionaries = [defaults objectForKey:RestlessApplicationsPreferenceKey];
    NSMutableArray *entryArray   = [NSMutableArray array];

    for (NSDictionary *dictionary in dictionaries) {
        [entryArray addObject:[[Entry alloc] initWithDictionary:dictionary]];
    }

    [self _setManualPreventionActive:[defaults boolForKey:ManualPreventionKey]];

    _entryArrayController = [[NSArrayController alloc] initWithContent:entryArray];
    [_entryArrayController addObserver:self forKeyPath:@"arrangedObjects" options:0 context:NULL];

    NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES];
    [_entryArrayController setSortDescriptors:@[ sortDescriptor ]];
}


- (void) _saveState
{
    NSMutableArray *dictionaries = [NSMutableArray array];

    for (Entry *entry in [_entryArrayController arrangedObjects]) {
        [dictionaries addObject:[entry dictionaryRepresentation]];
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:dictionaries forKey:RestlessApplicationsPreferenceKey];
    [defaults setBool:_manualPreventionActive forKey:ManualPreventionKey];
}


- (void) _updateLaunchHelper
{
    BOOL launchAtLogin = [[NSUserDefaults standardUserDefaults] boolForKey:LaunchAtLoginPreferenceKey];

    if (@available(macOS 13.0, *)) {
        SMAppService *service = [SMAppService mainAppService];
        NSError *error = nil;
        BOOL ok = YES;

        if (launchAtLogin) {
            if (service.status != SMAppServiceStatusEnabled) {
                ok = [service registerAndReturnError:&error];
            }
        } else {
            if (service.status == SMAppServiceStatusEnabled) {
                ok = [service unregisterAndReturnError:&error];
            }
        }

        if (!ok && launchAtLogin) {
            NSLog(@"Failed to register Login Item via SMAppService: %@", error);
            [[NSUserDefaults standardUserDefaults] setBool:NO forKey:LaunchAtLoginPreferenceKey];
        }
        return;
    }

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CFStringRef bundleID = (__bridge CFStringRef)kFermataLauncherBundleID;

    if (launchAtLogin) {
        if (!SMLoginItemSetEnabled(bundleID, YES)) {
            NSAlert *alert = [[NSAlert alloc] init];
            [alert setInformativeText:FermataLocalizedString(@"alert.login_item.failed")];
            [alert runModal];

            [[NSUserDefaults standardUserDefaults] setBool:NO forKey:LaunchAtLoginPreferenceKey];
        }
    } else {
        SMLoginItemSetEnabled(bundleID, NO);
    }
#pragma clang diagnostic pop
}


- (void) _handleUserDefaultsDidChangeNotification:(NSNotification *)note
{
    [self _updateLaunchHelper];
    [self _updateTimer];
}


- (void) _handleEntryDidUpdateNotification:(NSNotification *)note
{
    [self _updateEngineManually:NO];
    [self _saveState];
}


- (void) _handleLanguageDidChangeNotification:(NSNotification *)note
{
    [self _applyLocalization];
}


- (void) _handleFermataUpdateNotification:(NSNotification *)note
{
    [self _updateEngineManually:NO];
}


- (void) _setManualPreventionActive:(BOOL)manualPreventionActive
{
    if (_manualPreventionActive != manualPreventionActive) {
        _manualPreventionActive = manualPreventionActive;
        _manualPreventionStartTime = manualPreventionActive ? [NSDate timeIntervalSinceReferenceDate] : 0;
    }

    if (_manualPreventionActive && !_manualPreventionTimer) {
        __weak typeof(self) weakSelf = self;

        _manualPreventionTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 repeats:YES block:^(NSTimer *timer) {
            [weakSelf _updateStatusItem];
        }];

    } else if (!_manualPreventionActive && _manualPreventionTimer) {
        [_manualPreventionTimer invalidate];
        _manualPreventionTimer = nil;
    }

    [self _updateEngineManually:YES];
    [self _saveState];
}


- (NSImage *) _statusItemImageWithPercentage:(CGFloat)percentage
{
    NSImage *onImage = _onImage;

    CGRect onImageRect = CGRectZero;
    onImageRect.size = [onImage size];

    CGRect masterRect = onImageRect;
    masterRect.size.height += 4;
    onImageRect.origin.y += 2;

    NSImage *image = [NSImage imageWithSize:masterRect.size flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
        [onImage drawInRect:onImageRect];

        CGRect barRect = CGRectInset(masterRect, 2, 0);
        barRect.size.height = 2;
        [[NSBezierPath bezierPathWithRoundedRect:barRect xRadius:1 yRadius:1] addClip];

        [[NSColor colorWithWhite:0.0 alpha:0.25] set];
        [[NSBezierPath bezierPathWithRect:barRect] fill];

        CGRect activeBarRect = barRect;
        activeBarRect.size.width *= percentage;
        [[NSColor blackColor] set];
        [[NSBezierPath bezierPathWithRect:activeBarRect] fill];

        return YES;
    }];

    [image setTemplate:YES];

    return image;
}


- (void) _updateStatusItem
{
    NSImage *image = nil;

    if ([_engine isPreventingLidCloseSleep]) {
        NSInteger durationInMinutes = [[NSUserDefaults standardUserDefaults] integerForKey:ManualDurationKey];

        if (_manualPreventionActive && durationInMinutes) {
            NSTimeInterval duration  = durationInMinutes * 60;
            NSTimeInterval remaining = (_manualPreventionStartTime + duration) - [NSDate timeIntervalSinceReferenceDate];

            CGFloat percent = remaining / duration;
            if (percent > 1) percent = 1;
            if (percent < 0) percent = 0;

            image = [self _statusItemImageWithPercentage:percent];

        } else {
            image = _onImage;
        }

    } else {
        image = _offImage;
    }

    if (_statusItem.button) {
        _statusItem.button.image = image;
    }
}


- (void) _updateEngineManually:(BOOL)isManual
{
    BOOL shouldPrevent = NO;

    if (_applicationIsTerminating) return;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    NSTimeInterval reenableDelay = [defaults doubleForKey:ReenableDelayKey];
    if (isManual) reenableDelay = 0;

    // Step 1 - Check manual trigger
    //
    NSMutableArray<NSString *> *triggerNames = [NSMutableArray array];

    if (_manualPreventionActive) {
        shouldPrevent = YES;

        NSInteger durationInMinutes = [defaults integerForKey:ManualDurationKey];

        if (durationInMinutes) {
            NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];

            if (now > (_manualPreventionStartTime + (durationInMinutes * 60.0))) {
                [self _setManualPreventionActive:NO];
                shouldPrevent = NO;
                reenableDelay = 0;
            }
        }

        if (shouldPrevent) {
            [triggerNames addObject:FermataLocalizedString(@"menu.status.manual")];
        }
    }

    // Step 2 - Check watched applications & active idle-sleep assertions
    //
    NSDictionary<NSString *, NSArray<NSString *> *> *assertionsByBundleID = [_engine idleSleepAssertionsByBundleIdentifier];

    for (Entry *entry in [_entryArrayController arrangedObjects]) {
        NSString  *bundleIdentifier = [entry bundleIdentifier];
        EntryType  type             = [entry type];

        if (!bundleIdentifier) continue;

        NSArray<NSString *> *assertions = assertionsByBundleID[bundleIdentifier];
        BOOL isRunning = ([[NSRunningApplication runningApplicationsWithBundleIdentifier:bundleIdentifier] count] > 0);

        if (assertions.count > 0) {
            entry.runtimeStatus = EntryRuntimeStatusAsserting;
            entry.activeAssertionDescriptions = assertions;
        } else if (isRunning) {
            entry.runtimeStatus = EntryRuntimeStatusRunningIdle;
            entry.activeAssertionDescriptions = nil;
        } else {
            entry.runtimeStatus = EntryRuntimeStatusNotRunning;
            entry.activeAssertionDescriptions = nil;
        }

        if (type == EntryTypePreventLidCloseSleepWhenRunning && isRunning) {
            shouldPrevent = YES;
            if (entry.name.length > 0 && ![triggerNames containsObject:entry.name]) {
                [triggerNames addObject:entry.name];
            }
        } else if (type == EntryTypePreventLidCloseSleepWhenIdleSleepPrevented && assertions.count > 0) {
            shouldPrevent = YES;
            if (entry.name.length > 0 && ![triggerNames containsObject:entry.name]) {
                [triggerNames addObject:entry.name];
            }
        }
    }

    _activeTriggerSummary = triggerNames.count > 0 ? [triggerNames componentsJoinedByString:@", "] : nil;

    [_engine setAlsoPreventDisplaySleep:[defaults boolForKey:AlsoPreventDisplaySleepKey]];
    [_engine setSleepDisplayOnLidClose:[defaults boolForKey:SleepDisplayOnLidCloseKey]];

    if (shouldPrevent) {
        [_engine preventLidCloseSleep];

    } else {
        [_engine allowLidCloseSleepAfter:reenableDelay];
    }

    [self _updateStatusMenuItem];
    if (_preferencesController.window.isVisible) {
        [_preferencesController refreshAssertionStatuses];
    }
}


#pragma mark - KVO

- (void) observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    if ([object isEqual:_engine]) {
        [self _updateStatusItem];
        [self _updateStatusMenuItem];

    } else {
        [self _updateEngineManually:NO];
        [self _saveState];
    }
}


#pragma mark - IBActions

- (IBAction) preventLidCloseSleep:(id)sender
{
    if (!_engine.isHelperAvailable) {
        [_engine checkHelper];
        if (!_engine.isHelperAvailable) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = FermataLocalizedString(@"alert.helper_missing.title");
            alert.informativeText = FermataLocalizedString(@"alert.helper_missing.body");
            [alert runModal];
            return;
        }
    }

    if (!_manualPreventionActive) {
        [self _setManualPreventionActive:YES];
    } else {
        [self _setManualPreventionActive:NO];
    }
}


- (IBAction) showPreferences:(id)sender
{
    if (!_preferencesController) {
        _preferencesController = [[PreferencesController alloc] init];
        [_preferencesController setEntryArrayController:_entryArrayController];
        [_preferencesController setEngine:_engine];
    }

    [_preferencesController showWindow:self];
    [NSApp activateIgnoringOtherApps:YES];
}


@end
