// (c) 2017-2024 Ricci Adams
// Modified for Apple Silicon and reliability improvements by Masahiro Fujimoto
// MIT License (or) 1-clause BSD License

@import AppKit;

@class RestlessEngine;

@interface PreferencesController : NSWindowController <NSTableViewDelegate, NSWindowDelegate>

@property (nonatomic) NSArrayController *entryArrayController;
@property (nonatomic, weak) RestlessEngine *engine;

- (void) refreshAssertionStatuses;

@end
