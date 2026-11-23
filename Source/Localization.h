// (c) 2026 Masahiro Fujimoto
// MIT License (or) 1-clause BSD License

#import <Foundation/Foundation.h>

extern NSString * const FermataLanguagePreferenceKey;
extern NSString * const FermataLanguageDidChangeNotification;

extern NSString * const FermataLanguageValueSystem;
extern NSString * const FermataLanguageValueEnglish;
extern NSString * const FermataLanguageValueJapanese;

NSString *FermataCurrentLanguageCode(void);
NSString *FermataLocalizedString(NSString *key);
