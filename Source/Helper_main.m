// (c) 2018-2024 Ricci Adams
// Modified for Apple Silicon and reliability improvements by Masahiro Fujimoto
// MIT License (or) 1-clause BSD License

#import <Foundation/Foundation.h>
#import <IOKit/IOReturn.h>

#import "AppleSPI.h"
#import "HelperProtocol.h"


@interface Helper : NSObject <NSXPCListenerDelegate, HelperProtocol>
@end

@implementation Helper {
    NSXPCListener *_listener;
    dispatch_queue_t _queue;
    NSMutableSet<NSXPCConnection *> *_activeConnections;
    BOOL _preventingSleep;
    dispatch_source_t _sigTermSource;
    dispatch_source_t _sigIntSource;
}


- (instancetype) init
{
    if (self = [super init]) {
        _queue = dispatch_queue_create("com.fujimotomasahiro.Fermata.Helper.queue", DISPATCH_QUEUE_SERIAL);
        _activeConnections = [NSMutableSet set];
        _preventingSleep = NO;

        _listener = [[NSXPCListener alloc] initWithMachServiceName:kHelperMachServiceName];
        [_listener setDelegate:self];

        [self _setupSignalHandlers];
    }

    return self;
}


- (void) _setupSignalHandlers
{
    signal(SIGTERM, SIG_IGN);
    signal(SIGINT, SIG_IGN);

    __weak typeof(self) weakSelf = self;

    void (^handleShutdown)(void) = ^{
        __strong typeof(self) strongSelf = weakSelf;
        if (strongSelf && strongSelf->_preventingSleep) {
            IOPMSetSystemPowerSetting(kIOPMSleepDisabledKey, kCFBooleanFalse);
            strongSelf->_preventingSleep = NO;
        }
        exit(0);
    };

    _sigTermSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, _queue);
    dispatch_source_set_event_handler(_sigTermSource, handleShutdown);
    dispatch_resume(_sigTermSource);

    _sigIntSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGINT, 0, _queue);
    dispatch_source_set_event_handler(_sigIntSource, handleShutdown);
    dispatch_resume(_sigIntSource);
}


- (void) run
{
    [_listener resume];
    dispatch_main();
}


- (BOOL) listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection
{
    [newConnection setExportedInterface:[NSXPCInterface interfaceWithProtocol:@protocol(HelperProtocol)]];
    [newConnection setExportedObject:self];

    __weak typeof(self) weakSelf = self;
    __weak NSXPCConnection *weakConnection = newConnection;

    [newConnection setInvalidationHandler:^{
        __strong typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;

        dispatch_async(strongSelf->_queue, ^{
            NSXPCConnection *conn = weakConnection;
            if (conn) {
                [strongSelf->_activeConnections removeObject:conn];
            }

            // Fail-safe: if all clients disconnected (e.g. app crashed or force-quit),
            // restore normal lid-close sleep immediately so the Mac never stays awake indefinitely.
            if ([strongSelf->_activeConnections count] == 0 && strongSelf->_preventingSleep) {
                IOPMSetSystemPowerSetting(kIOPMSleepDisabledKey, kCFBooleanFalse);
                strongSelf->_preventingSleep = NO;
            }
        });
    }];

    dispatch_sync(_queue, ^{
        [_activeConnections addObject:newConnection];
    });

    [newConnection resume];
    return YES;
}


- (void) preventSleepWithReply:(void (^)(NSInteger error))reply
{
    dispatch_async(_queue, ^{
        NSInteger status = IOPMSetSystemPowerSetting(kIOPMSleepDisabledKey, kCFBooleanTrue);
        if (status == kIOReturnSuccess) {
            self->_preventingSleep = YES;
        }
        if (reply) reply(status);
    });
}


- (void) allowSleepWithReply:(void (^)(NSInteger error))reply
{
    dispatch_async(_queue, ^{
        NSInteger status = IOPMSetSystemPowerSetting(kIOPMSleepDisabledKey, kCFBooleanFalse);
        if (status == kIOReturnSuccess) {
            self->_preventingSleep = NO;
        }
        if (reply) reply(status);
    });
}


- (void) requestVersionWithReply:(void (^)(NSInteger version))reply
{
    if (reply) reply(kHelperVersion);
}


@end


int main(int argc, char *argv[])
{
    @autoreleasepool {
        Helper *helper = [[Helper alloc] init];
        [helper run];
    }

    return 0;
}
