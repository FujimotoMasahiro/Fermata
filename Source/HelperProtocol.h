// (c) 2018-2024 Ricci Adams
// Modified for Apple Silicon and reliability improvements by Masahiro Fujimoto
// MIT License (or) 1-clause BSD License

#import <Foundation/Foundation.h>

#define kHelperMachServiceName @"com.fujimotomasahiro.Fermata.Helper"
#define kHelperVersion 2

@protocol HelperProtocol
@required
- (void) preventSleepWithReply:(void (^)(NSInteger error))reply;
- (void) allowSleepWithReply:(void (^)(NSInteger error))reply;
- (void) requestVersionWithReply:(void (^)(NSInteger version))reply;
@end
