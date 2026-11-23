// (c) 2017-2024 Ricci Adams
// Modified for Apple Silicon and reliability improvements by Masahiro Fujimoto
// MIT License (or) 1-clause BSD License

#import <Foundation/Foundation.h>

extern NSString * const EntryDidUpdateNotification;

typedef NS_ENUM(NSInteger, EntryType) {
    EntryTypeNone,
    EntryTypePreventLidCloseSleepWhenRunning,
    EntryTypePreventLidCloseSleepWhenIdleSleepPrevented
};

typedef NS_ENUM(NSInteger, EntryRuntimeStatus) {
    EntryRuntimeStatusNotRunning = 0,
    EntryRuntimeStatusRunningIdle = 1,
    EntryRuntimeStatusAsserting = 2
};


@interface Entry : NSObject

- (instancetype) initWithDictionary:(NSDictionary *)dictionary;

@property (nonatomic, readonly) NSDictionary *dictionaryRepresentation;

@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *bundleIdentifier;

@property (nonatomic) EntryType type;

// Runtime-only status (not persisted)
@property (nonatomic) EntryRuntimeStatus runtimeStatus;
@property (nonatomic, copy) NSArray<NSString *> *activeAssertionDescriptions;

@end
