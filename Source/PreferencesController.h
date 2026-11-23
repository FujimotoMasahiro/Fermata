// (c) 2017-2024 Ricci Adams
// Modified for Apple Silicon and reliability improvements by Masahiro Fujimoto
// MIT License (or) 1-clause BSD License

@import AppKit;

@interface PreferencesController : NSWindowController <NSTableViewDelegate>

@property (nonatomic) NSArrayController *entryArrayController;

@end
