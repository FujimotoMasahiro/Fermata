// (c) 2017-2024 Ricci Adams
// Modified for Apple Silicon and reliability improvements by Masahiro Fujimoto
// MIT License (or) 1-clause BSD License

#import <Cocoa/Cocoa.h>

@interface LaunchFermataAppDelegate : NSObject <NSApplicationDelegate>
@end

@implementation LaunchFermataAppDelegate

- (void) applicationDidFinishLaunching:(NSNotification *)aNotification
{
    NSArray *runningApplications = [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.fujimotomasahiro.Fermata"];
    BOOL     needsLaunch         = [runningApplications count] == 0;

    if (needsLaunch) {
        NSString       *path       = [[NSBundle mainBundle] bundlePath];
        NSMutableArray *components = [[path pathComponents] mutableCopy];

        if ([components count] > 4) {
            [components removeLastObject];
            [components removeLastObject];
            [components removeLastObject];
            [components removeLastObject];

            NSString *appPath = [NSString pathWithComponents:components];
            NSURL *appURL = [NSURL fileURLWithPath:appPath];
            NSWorkspaceOpenConfiguration *config = [NSWorkspaceOpenConfiguration configuration];

            [[NSWorkspace sharedWorkspace] openApplicationAtURL:appURL
                                                  configuration:config
                                              completionHandler:^(NSRunningApplication *app, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [NSApp terminate:nil];
                });
            }];
            return;
        }
    }

    [NSApp terminate:nil];
}

@end


int main(int argc, const char * argv[])
{
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        LaunchFermataAppDelegate *appDelegate = [[LaunchFermataAppDelegate alloc] init];

        [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
        [application setDelegate:appDelegate];
        [application run];
    }
    return 0;
}
