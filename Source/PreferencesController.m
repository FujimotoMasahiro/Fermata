// (c) 2017-2024 Ricci Adams
// Modified for Apple Silicon and reliability improvements by Masahiro Fujimoto
// MIT License (or) 1-clause BSD License

#import "PreferencesController.h"
#import "Entry.h"
#import "Localization.h"


@import ServiceManagement;
@import UniformTypeIdentifiers;


#pragma mark - Info Popover Button

@class FermataInfoButton;

@protocol FermataInfoButtonDelegate <NSObject>
- (void) infoButtonDidHoverEnter:(FermataInfoButton *)button;
- (void) infoButtonDidHoverExit:(FermataInfoButton *)button;
- (void) infoButtonDidClick:(FermataInfoButton *)button;
@end

@interface FermataInfoButton : NSButton
@property (nonatomic, copy) NSString *helpTitleKey;
@property (nonatomic, copy) NSString *helpBodyKey;
@property (nonatomic, weak) id<FermataInfoButtonDelegate> infoDelegate;
@end

@implementation FermataInfoButton {
    NSTrackingArea *_trackingArea;
}

- (instancetype) initWithTitleKey:(NSString *)titleKey bodyKey:(NSString *)bodyKey delegate:(id<FermataInfoButtonDelegate>)delegate
{
    if ((self = [super initWithFrame:NSMakeRect(0, 0, 18, 18)])) {
        _helpTitleKey = [titleKey copy];
        _helpBodyKey  = [bodyKey copy];
        _infoDelegate = delegate;

        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.bordered = NO;
        self.title = @"";
        self.bezelStyle = NSBezelStyleInline;
        [self setButtonType:NSButtonTypeMomentaryChange];

        NSImage *symbol = [NSImage imageWithSystemSymbolName:@"info.circle" accessibilityDescription:@"Help"];
        if (symbol) {
            NSImageSymbolConfiguration *cfg = [NSImageSymbolConfiguration configurationWithPointSize:13.0 weight:NSFontWeightRegular];
            self.image = [symbol imageWithSymbolConfiguration:cfg] ?: symbol;
            self.imageScaling = NSImageScaleProportionallyDown;
        } else {
            self.title = @"?";
        }
        self.contentTintColor = [NSColor secondaryLabelColor];

        self.target = self;
        self.action = @selector(_handleClick:);

        [NSLayoutConstraint activateConstraints:@[
            [self.widthAnchor constraintEqualToConstant:18.0],
            [self.heightAnchor constraintEqualToConstant:18.0]
        ]];
    }
    return self;
}

- (void) updateTrackingAreas
{
    [super updateTrackingAreas];

    if (_trackingArea) {
        [self removeTrackingArea:_trackingArea];
        _trackingArea = nil;
    }

    NSTrackingAreaOptions options = NSTrackingMouseEnteredAndExited |
                                    NSTrackingActiveAlways |
                                    NSTrackingInVisibleRect;
    _trackingArea = [[NSTrackingArea alloc] initWithRect:self.bounds options:options owner:self userInfo:nil];
    [self addTrackingArea:_trackingArea];
}

- (void) mouseEntered:(NSEvent *)event
{
    self.contentTintColor = [NSColor controlAccentColor];
    [self.infoDelegate infoButtonDidHoverEnter:self];
}

- (void) mouseExited:(NSEvent *)event
{
    self.contentTintColor = [NSColor secondaryLabelColor];
    [self.infoDelegate infoButtonDidHoverExit:self];
}

- (void) _handleClick:(id)sender
{
    [self.infoDelegate infoButtonDidClick:self];
}

@end


#pragma mark - PreferencesController

@interface PreferencesController () <FermataInfoButtonDelegate, NSPopoverDelegate>
@property (nonatomic) IBOutlet NSTableView *tableView;

@property (nonatomic, weak) IBOutlet NSTextField *autoHeaderLabel;
@property (nonatomic, weak) IBOutlet NSButton *addButton;
@property (nonatomic, weak) IBOutlet NSButton *removeButton;

@property (nonatomic, weak) IBOutlet NSTextField *updateFrequencyLabel;
@property (nonatomic, weak) IBOutlet NSPopUpButton *updateFrequencyPopUp;

@property (nonatomic, weak) IBOutlet NSTextField *reenableDelayLabel;
@property (nonatomic, weak) IBOutlet NSPopUpButton *reenableDelayPopUp;

@property (nonatomic, weak) IBOutlet NSTextField *manualDurationLabel;
@property (nonatomic, weak) IBOutlet NSPopUpButton *manualDurationPopUp;

@property (nonatomic, weak) IBOutlet NSTextField *alsoPreventLabel;
@property (nonatomic, weak) IBOutlet NSButton *diskSleepCheckbox;
@property (nonatomic, weak) IBOutlet NSButton *displaySleepCheckbox;

@property (nonatomic, weak) IBOutlet NSTextField *languageLabel;
@property (nonatomic, weak) IBOutlet NSPopUpButton *languagePopUp;

@property (nonatomic, weak) IBOutlet NSButton *launchAtLoginCheckbox;
@end


@implementation PreferencesController {
    NSPopover *_helpPopover;
    __weak FermataInfoButton *_activeInfoButton;
    BOOL _popoverPinnedByClick;
    NSUInteger _hoverSequence;
}

- (NSString *) windowNibName
{
    return @"Preferences";
}


- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}


- (void) windowDidLoad
{
    [super windowDidLoad];

    self.window.allowsToolTipsWhenApplicationIsInactive = YES;
    self.tableView.delegate = self;

    [self _installInfoButtons];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_handleLanguageDidChange:)
                                                 name:FermataLanguageDidChangeNotification
                                               object:nil];

    [self _syncLanguageSelection];
    [self _applyLocalization];
}


#pragma mark - Info Popover Setup & Behavior

- (void) _installInfoButtons
{
    NSView *contentView = self.window.contentView;
    if (!contentView) return;

    // 1. Auto-list header (aligned to right edge of content)
    FermataInfoButton *autoBtn = [[FermataInfoButton alloc] initWithTitleKey:@"help.title.auto_list"
                                                                     bodyKey:@"tooltip.auto_list"
                                                                    delegate:self];
    [contentView addSubview:autoBtn];
    [NSLayoutConstraint activateConstraints:@[
        [autoBtn.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20.0],
        [autoBtn.centerYAnchor constraintEqualToAnchor:self.autoHeaderLabel.centerYAnchor]
    ]];

    // Helper to align info buttons along the right side of the popup column
    void (^addAlignedToPopUpColumn)(NSView *, NSString *, NSString *) = ^(NSView *anchorView, NSString *titleKey, NSString *bodyKey) {
        if (!anchorView || !self.updateFrequencyPopUp) return;
        FermataInfoButton *btn = [[FermataInfoButton alloc] initWithTitleKey:titleKey bodyKey:bodyKey delegate:self];
        [contentView addSubview:btn];
        [NSLayoutConstraint activateConstraints:@[
            [btn.leadingAnchor constraintEqualToAnchor:self.updateFrequencyPopUp.trailingAnchor constant:8.0],
            [btn.centerYAnchor constraintEqualToAnchor:anchorView.centerYAnchor]
        ]];
    };

    addAlignedToPopUpColumn(self.updateFrequencyPopUp, @"help.title.update_freq",     @"tooltip.update_freq");
    addAlignedToPopUpColumn(self.reenableDelayPopUp,   @"help.title.reenable_delay",  @"tooltip.reenable_delay");
    addAlignedToPopUpColumn(self.manualDurationPopUp,  @"help.title.manual_duration", @"tooltip.manual_duration");
    addAlignedToPopUpColumn(self.diskSleepCheckbox,    @"help.title.disk_sleep",      @"tooltip.disk_sleep");
    addAlignedToPopUpColumn(self.displaySleepCheckbox, @"help.title.display_sleep",   @"tooltip.display_sleep");
    addAlignedToPopUpColumn(self.languagePopUp,        @"help.title.language",        @"tooltip.language");

    // 8. Launch at login checkbox (placed right next to the centered checkbox)
    if (self.launchAtLoginCheckbox) {
        FermataInfoButton *loginBtn = [[FermataInfoButton alloc] initWithTitleKey:@"help.title.launch_at_login"
                                                                          bodyKey:@"tooltip.launch_at_login"
                                                                         delegate:self];
        [contentView addSubview:loginBtn];
        [NSLayoutConstraint activateConstraints:@[
            [loginBtn.leadingAnchor constraintEqualToAnchor:self.launchAtLoginCheckbox.trailingAnchor constant:6.0],
            [loginBtn.centerYAnchor constraintEqualToAnchor:self.launchAtLoginCheckbox.centerYAnchor]
        ]];
    }
}


- (void) _showPopoverForInfoButton:(FermataInfoButton *)button pinned:(BOOL)pinned
{
    if (!button || !button.window) return;

    if (_helpPopover.isShown && _activeInfoButton == button) {
        if (pinned) {
            _popoverPinnedByClick = YES;
            _helpPopover.behavior = NSPopoverBehaviorTransient;
        }
        return;
    }

    if (_helpPopover.isShown) {
        [_helpPopover performClose:nil];
    }

    NSString *title = FermataLocalizedString(button.helpTitleKey);
    NSString *body  = FermataLocalizedString(button.helpBodyKey);

    NSViewController *vc = [[NSViewController alloc] init];
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 290, 80)];

    NSTextField *titleLabel = [NSTextField wrappingLabelWithString:title];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    titleLabel.font = [NSFont boldSystemFontOfSize:12.5];
    titleLabel.textColor = [NSColor labelColor];

    NSTextField *bodyLabel = [NSTextField wrappingLabelWithString:body];
    bodyLabel.translatesAutoresizingMaskIntoConstraints = NO;
    bodyLabel.font = [NSFont systemFontOfSize:12.0];
    bodyLabel.textColor = [NSColor secondaryLabelColor];
    bodyLabel.preferredMaxLayoutWidth = 264.0;

    [container addSubview:titleLabel];
    [container addSubview:bodyLabel];

    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.topAnchor constraintEqualToAnchor:container.topAnchor constant:12.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:13.0],
        [titleLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-13.0],

        [bodyLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:6.0],
        [bodyLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:13.0],
        [bodyLabel.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-13.0],
        [bodyLabel.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-12.0],
        [bodyLabel.widthAnchor constraintEqualToConstant:264.0]
    ]];

    [container layoutSubtreeIfNeeded];
    NSSize fittingSize = container.fittingSize;
    container.frame = NSMakeRect(0, 0, fittingSize.width, fittingSize.height);
    vc.view = container;

    NSPopover *popover = [[NSPopover alloc] init];
    popover.contentViewController = vc;
    popover.contentSize = fittingSize;
    popover.animates = YES;
    popover.delegate = self;
    popover.behavior = pinned ? NSPopoverBehaviorTransient : NSPopoverBehaviorApplicationDefined;

    _helpPopover = popover;
    _activeInfoButton = button;
    _popoverPinnedByClick = pinned;

    [popover showRelativeToRect:button.bounds ofView:button preferredEdge:NSRectEdgeMaxX];
}


- (void) _closePopoverIfNotPinned
{
    if (_helpPopover.isShown && !_popoverPinnedByClick) {
        [_helpPopover performClose:nil];
    }
}


- (void) infoButtonDidHoverEnter:(FermataInfoButton *)button
{
    _hoverSequence++;
    NSUInteger seq = _hoverSequence;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.10 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self->_hoverSequence != seq) return;
        [self _showPopoverForInfoButton:button pinned:NO];
    });
}


- (void) infoButtonDidHoverExit:(FermataInfoButton *)button
{
    _hoverSequence++;
    NSUInteger seq = _hoverSequence;

    if (_popoverPinnedByClick) return;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.18 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if (self->_hoverSequence != seq) return;
        [self _closePopoverIfNotPinned];
    });
}


- (void) infoButtonDidClick:(FermataInfoButton *)button
{
    _hoverSequence++;
    if (_helpPopover.isShown && _activeInfoButton == button && _popoverPinnedByClick) {
        [_helpPopover performClose:nil];
        return;
    }
    [self _showPopoverForInfoButton:button pinned:YES];
}


- (void) popoverDidClose:(NSNotification *)notification
{
    if (notification.object == _helpPopover) {
        _activeInfoButton = nil;
        _popoverPinnedByClick = NO;
    }
}


#pragma mark - Localization

- (void) _handleLanguageDidChange:(NSNotification *)note
{
    if (_helpPopover.isShown) {
        [_helpPopover performClose:nil];
    }
    [self _syncLanguageSelection];
    [self _applyLocalization];
}


- (void) _syncLanguageSelection
{
    NSString *pref = [[NSUserDefaults standardUserDefaults] stringForKey:FermataLanguagePreferenceKey];
    NSInteger tag = 0;

    if ([pref isEqualToString:FermataLanguageValueEnglish]) {
        tag = 1;
    } else if ([pref isEqualToString:FermataLanguageValueJapanese]) {
        tag = 2;
    }

    [self.languagePopUp selectItemWithTag:tag];
}


- (void) _setTitle:(NSString *)title forPopUp:(NSPopUpButton *)popUp itemWithTag:(NSInteger)tag
{
    NSMenuItem *item = [popUp.menu itemWithTag:tag];
    if (item) {
        item.title = title;
    }
}


- (void) _setTitle:(NSString *)title toolTip:(NSString *)toolTip forPopUp:(NSPopUpButton *)popUp itemWithTag:(NSInteger)tag
{
    NSMenuItem *item = [popUp.menu itemWithTag:tag];
    if (item) {
        item.title = title;
        item.toolTip = toolTip;
    }
}


- (void) _localizeRowView:(NSTableRowView *)rowView
{
    if (!rowView) return;

    NSTableCellView *cellView = [rowView viewAtColumn:0];
    if (![cellView isKindOfClass:[NSView class]]) return;

    for (NSView *subview in cellView.subviews) {
        if ([subview isKindOfClass:[NSPopUpButton class]]) {
            NSPopUpButton *popUp = (NSPopUpButton *)subview;
            [self _setTitle:FermataLocalizedString(@"prefs.action.idle_sleep")
                    toolTip:FermataLocalizedString(@"tooltip.action.idle_sleep")
                   forPopUp:popUp
                itemWithTag:2];
            [self _setTitle:FermataLocalizedString(@"prefs.action.running")
                    toolTip:FermataLocalizedString(@"tooltip.action.running")
                   forPopUp:popUp
                itemWithTag:1];
            popUp.toolTip = FermataLocalizedString(@"tooltip.action_popup");
            [popUp synchronizeTitleAndSelectedItem];
        }
    }
}


- (void) _applyLocalization
{
    self.window.title = FermataLocalizedString(@"prefs.title");

    // Watched apps section
    self.autoHeaderLabel.stringValue = FermataLocalizedString(@"prefs.auto_header");
    self.autoHeaderLabel.toolTip     = FermataLocalizedString(@"tooltip.auto_list");
    self.tableView.toolTip           = FermataLocalizedString(@"tooltip.auto_list");

    self.addButton.title             = FermataLocalizedString(@"prefs.add_app");
    self.addButton.toolTip           = FermataLocalizedString(@"tooltip.add_app");
    self.removeButton.title          = FermataLocalizedString(@"prefs.remove_app");
    self.removeButton.toolTip        = FermataLocalizedString(@"tooltip.remove_app");

    // Update frequency
    NSString *updateFreqTip = FermataLocalizedString(@"tooltip.update_freq");
    self.updateFrequencyLabel.stringValue = FermataLocalizedString(@"prefs.update_freq");
    self.updateFrequencyLabel.toolTip     = updateFreqTip;
    self.updateFrequencyPopUp.toolTip     = updateFreqTip;
    [self _setTitle:FermataLocalizedString(@"duration.5s_interval")  forPopUp:self.updateFrequencyPopUp itemWithTag:5];
    [self _setTitle:FermataLocalizedString(@"duration.10s_interval") forPopUp:self.updateFrequencyPopUp itemWithTag:10];
    [self _setTitle:FermataLocalizedString(@"duration.15s_interval") forPopUp:self.updateFrequencyPopUp itemWithTag:15];
    [self _setTitle:FermataLocalizedString(@"duration.30s_interval") forPopUp:self.updateFrequencyPopUp itemWithTag:30];
    [self.updateFrequencyPopUp synchronizeTitleAndSelectedItem];

    // Delay before re-enabling
    NSString *delayTip = FermataLocalizedString(@"tooltip.reenable_delay");
    self.reenableDelayLabel.stringValue = FermataLocalizedString(@"prefs.reenable_delay");
    self.reenableDelayLabel.toolTip     = delayTip;
    self.reenableDelayPopUp.toolTip     = delayTip;
    [self _setTitle:FermataLocalizedString(@"duration.none") forPopUp:self.reenableDelayPopUp itemWithTag:0];
    [self _setTitle:FermataLocalizedString(@"duration.1s")   forPopUp:self.reenableDelayPopUp itemWithTag:1];
    [self _setTitle:FermataLocalizedString(@"duration.5s")   forPopUp:self.reenableDelayPopUp itemWithTag:5];
    [self _setTitle:FermataLocalizedString(@"duration.10s")  forPopUp:self.reenableDelayPopUp itemWithTag:10];
    [self _setTitle:FermataLocalizedString(@"duration.15s")  forPopUp:self.reenableDelayPopUp itemWithTag:15];
    [self _setTitle:FermataLocalizedString(@"duration.30s")  forPopUp:self.reenableDelayPopUp itemWithTag:30];
    [self.reenableDelayPopUp synchronizeTitleAndSelectedItem];

    // Manual activation duration
    NSString *manualTip = FermataLocalizedString(@"tooltip.manual_duration");
    self.manualDurationLabel.stringValue = FermataLocalizedString(@"prefs.manual_duration");
    self.manualDurationLabel.toolTip     = manualTip;
    self.manualDurationPopUp.toolTip     = manualTip;
    [self _setTitle:FermataLocalizedString(@"duration.forever") forPopUp:self.manualDurationPopUp itemWithTag:0];
    [self _setTitle:FermataLocalizedString(@"duration.1m")      forPopUp:self.manualDurationPopUp itemWithTag:1];
    [self _setTitle:FermataLocalizedString(@"duration.5m")      forPopUp:self.manualDurationPopUp itemWithTag:5];
    [self _setTitle:FermataLocalizedString(@"duration.10m")     forPopUp:self.manualDurationPopUp itemWithTag:10];
    [self _setTitle:FermataLocalizedString(@"duration.15m")     forPopUp:self.manualDurationPopUp itemWithTag:15];
    [self _setTitle:FermataLocalizedString(@"duration.30m")     forPopUp:self.manualDurationPopUp itemWithTag:30];
    [self.manualDurationPopUp synchronizeTitleAndSelectedItem];

    // Additional sleep assertions
    self.alsoPreventLabel.stringValue   = FermataLocalizedString(@"prefs.also_prevent");
    self.alsoPreventLabel.toolTip       = FermataLocalizedString(@"tooltip.also_prevent");
    self.diskSleepCheckbox.title        = FermataLocalizedString(@"prefs.disk_sleep");
    self.diskSleepCheckbox.toolTip      = FermataLocalizedString(@"tooltip.disk_sleep");
    self.displaySleepCheckbox.title     = FermataLocalizedString(@"prefs.display_sleep");
    self.displaySleepCheckbox.toolTip   = FermataLocalizedString(@"tooltip.display_sleep");

    // Language
    NSString *langTip = FermataLocalizedString(@"tooltip.language");
    self.languageLabel.stringValue = FermataLocalizedString(@"prefs.language");
    self.languageLabel.toolTip     = langTip;
    self.languagePopUp.toolTip     = langTip;
    [self _setTitle:FermataLocalizedString(@"prefs.lang.system") forPopUp:self.languagePopUp itemWithTag:0];
    [self _setTitle:FermataLocalizedString(@"prefs.lang.en")     forPopUp:self.languagePopUp itemWithTag:1];
    [self _setTitle:FermataLocalizedString(@"prefs.lang.ja")     forPopUp:self.languagePopUp itemWithTag:2];
    [self.languagePopUp synchronizeTitleAndSelectedItem];

    // Launch at login
    self.launchAtLoginCheckbox.title   = FermataLocalizedString(@"prefs.launch_at_login");
    self.launchAtLoginCheckbox.toolTip = FermataLocalizedString(@"tooltip.launch_at_login");

    __weak typeof(self) weakSelf = self;
    [self.tableView enumerateAvailableRowViewsUsingBlock:^(NSTableRowView *rowView, NSInteger row) {
        [weakSelf _localizeRowView:rowView];
    }];
}


#pragma mark - NSTableViewDelegate

- (void) tableView:(NSTableView *)tableView didAddRowView:(NSTableRowView *)rowView forRow:(NSInteger)row
{
    [self _localizeRowView:rowView];
}


#pragma mark - IBActions

- (IBAction) changeLanguage:(id)sender
{
    NSInteger tag = [self.languagePopUp selectedTag];
    NSString *value = FermataLanguageValueSystem;

    if (tag == 1) {
        value = FermataLanguageValueEnglish;
    } else if (tag == 2) {
        value = FermataLanguageValueJapanese;
    }

    [[NSUserDefaults standardUserDefaults] setObject:value forKey:FermataLanguagePreferenceKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:FermataLanguageDidChangeNotification object:nil];
}


- (IBAction) addEntry:(id)sender
{
    NSOpenPanel *openPanel = [NSOpenPanel openPanel];

    [openPanel setAllowedContentTypes:@[ UTTypeApplicationBundle ]];

    [openPanel beginSheetModalForWindow:[self window] completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseAbort || result == NSModalResponseCancel) return;

        NSURL *URL = [openPanel URL];
        if (!URL) return;

        NSBundle *bundle = [NSBundle bundleWithURL:URL];

        if (bundle) {
            NSString *bundleIdentifier = [bundle bundleIdentifier];

            NSString *name = [[bundle localizedInfoDictionary] objectForKey:@"CFBundleDisplayName"];
            if (!name) name = [[bundle infoDictionary] objectForKey:@"CFBundleDisplayName"];
            if (!name) name = [[bundle localizedInfoDictionary] objectForKey:@"CFBundleName"];
            if (!name) name = [[bundle infoDictionary] objectForKey:@"CFBundleName"];
            if (!name) name = bundleIdentifier;

            if (bundleIdentifier && name) {
                Entry *entry = [[Entry alloc] init];

                [entry setName:name];
                [entry setBundleIdentifier:bundleIdentifier];
                [entry setType:EntryTypePreventLidCloseSleepWhenIdleSleepPrevented];

                [_entryArrayController addObject:entry];
            }
        }
    }];
}


- (IBAction) removeEntry:(id)sender
{
    [_entryArrayController removeObjects:[_entryArrayController selectedObjects]];
    [_entryArrayController setSelectedObjects:@[ ]];
}


@end
