// (c) 2017-2024 Ricci Adams
// Modified for Apple Silicon and reliability improvements by Masahiro Fujimoto
// MIT License (or) 1-clause BSD License

#import "PreferencesController.h"
#import "Entry.h"


@import ServiceManagement;
@import UniformTypeIdentifiers;

@interface PreferencesController ()
@property (nonatomic) IBOutlet NSTableView *tableView;
@end

@implementation PreferencesController {
}

- (NSString *) windowNibName
{
    return @"Preferences";
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
