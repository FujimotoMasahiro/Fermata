// (c) 2017-2024 Ricci Adams
// Modified for Apple Silicon and reliability improvements by Masahiro Fujimoto
// MIT License (or) 1-clause BSD License

#import "PreferencesController.h"
#import "Entry.h"
#import "Localization.h"


@import ServiceManagement;
@import UniformTypeIdentifiers;

@interface PreferencesController ()
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


@implementation PreferencesController

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

    self.tableView.delegate = self;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_handleLanguageDidChange:)
                                                 name:FermataLanguageDidChangeNotification
                                               object:nil];

    [self _syncLanguageSelection];
    [self _applyLocalization];
}


#pragma mark - Localization

- (void) _handleLanguageDidChange:(NSNotification *)note
{
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


- (void) _localizeRowView:(NSTableRowView *)rowView
{
    if (!rowView) return;

    NSTableCellView *cellView = [rowView viewAtColumn:0];
    if (![cellView isKindOfClass:[NSView class]]) return;

    for (NSView *subview in cellView.subviews) {
        if ([subview isKindOfClass:[NSPopUpButton class]]) {
            NSPopUpButton *popUp = (NSPopUpButton *)subview;
            [self _setTitle:FermataLocalizedString(@"prefs.action.idle_sleep") forPopUp:popUp itemWithTag:2];
            [self _setTitle:FermataLocalizedString(@"prefs.action.running")    forPopUp:popUp itemWithTag:1];
            [popUp synchronizeTitleAndSelectedItem];
        }
    }
}


- (void) _applyLocalization
{
    self.window.title = FermataLocalizedString(@"prefs.title");

    self.autoHeaderLabel.stringValue      = FermataLocalizedString(@"prefs.auto_header");
    self.addButton.title                  = FermataLocalizedString(@"prefs.add_app");
    self.removeButton.title               = FermataLocalizedString(@"prefs.remove_app");

    self.updateFrequencyLabel.stringValue = FermataLocalizedString(@"prefs.update_freq");
    [self _setTitle:FermataLocalizedString(@"duration.5s")  forPopUp:self.updateFrequencyPopUp itemWithTag:5];
    [self _setTitle:FermataLocalizedString(@"duration.10s") forPopUp:self.updateFrequencyPopUp itemWithTag:10];
    [self _setTitle:FermataLocalizedString(@"duration.15s") forPopUp:self.updateFrequencyPopUp itemWithTag:15];
    [self _setTitle:FermataLocalizedString(@"duration.30s") forPopUp:self.updateFrequencyPopUp itemWithTag:30];
    [self.updateFrequencyPopUp synchronizeTitleAndSelectedItem];

    self.reenableDelayLabel.stringValue   = FermataLocalizedString(@"prefs.reenable_delay");
    [self _setTitle:FermataLocalizedString(@"duration.none") forPopUp:self.reenableDelayPopUp itemWithTag:0];
    [self _setTitle:FermataLocalizedString(@"duration.1s")   forPopUp:self.reenableDelayPopUp itemWithTag:1];
    [self _setTitle:FermataLocalizedString(@"duration.5s")   forPopUp:self.reenableDelayPopUp itemWithTag:5];
    [self _setTitle:FermataLocalizedString(@"duration.10s")  forPopUp:self.reenableDelayPopUp itemWithTag:10];
    [self _setTitle:FermataLocalizedString(@"duration.15s")  forPopUp:self.reenableDelayPopUp itemWithTag:15];
    [self _setTitle:FermataLocalizedString(@"duration.30s")  forPopUp:self.reenableDelayPopUp itemWithTag:30];
    [self.reenableDelayPopUp synchronizeTitleAndSelectedItem];

    self.manualDurationLabel.stringValue  = FermataLocalizedString(@"prefs.manual_duration");
    [self _setTitle:FermataLocalizedString(@"duration.forever") forPopUp:self.manualDurationPopUp itemWithTag:0];
    [self _setTitle:FermataLocalizedString(@"duration.1m")      forPopUp:self.manualDurationPopUp itemWithTag:1];
    [self _setTitle:FermataLocalizedString(@"duration.5m")      forPopUp:self.manualDurationPopUp itemWithTag:5];
    [self _setTitle:FermataLocalizedString(@"duration.10m")     forPopUp:self.manualDurationPopUp itemWithTag:10];
    [self _setTitle:FermataLocalizedString(@"duration.15m")     forPopUp:self.manualDurationPopUp itemWithTag:15];
    [self _setTitle:FermataLocalizedString(@"duration.30m")     forPopUp:self.manualDurationPopUp itemWithTag:30];
    [self.manualDurationPopUp synchronizeTitleAndSelectedItem];

    self.alsoPreventLabel.stringValue     = FermataLocalizedString(@"prefs.also_prevent");
    self.diskSleepCheckbox.title          = FermataLocalizedString(@"prefs.disk_sleep");
    self.displaySleepCheckbox.title       = FermataLocalizedString(@"prefs.display_sleep");

    self.languageLabel.stringValue        = FermataLocalizedString(@"prefs.language");
    [self _setTitle:FermataLocalizedString(@"prefs.lang.system") forPopUp:self.languagePopUp itemWithTag:0];
    [self _setTitle:FermataLocalizedString(@"prefs.lang.en")     forPopUp:self.languagePopUp itemWithTag:1];
    [self _setTitle:FermataLocalizedString(@"prefs.lang.ja")     forPopUp:self.languagePopUp itemWithTag:2];
    [self.languagePopUp synchronizeTitleAndSelectedItem];

    self.launchAtLoginCheckbox.title      = FermataLocalizedString(@"prefs.launch_at_login");

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
