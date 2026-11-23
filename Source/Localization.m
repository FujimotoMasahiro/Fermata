// (c) 2026 Masahiro Fujimoto
// MIT License (or) 1-clause BSD License

#import "Localization.h"

NSString * const FermataLanguagePreferenceKey        = @"AppLanguage";
NSString * const FermataLanguageDidChangeNotification = @"FermataLanguageDidChangeNotification";

NSString * const FermataLanguageValueSystem   = @"system";
NSString * const FermataLanguageValueEnglish  = @"en";
NSString * const FermataLanguageValueJapanese = @"ja";


NSString *FermataCurrentLanguageCode(void)
{
    NSString *pref = [[NSUserDefaults standardUserDefaults] stringForKey:FermataLanguagePreferenceKey];

    if ([pref isEqualToString:FermataLanguageValueJapanese]) {
        return FermataLanguageValueJapanese;
    }
    if ([pref isEqualToString:FermataLanguageValueEnglish]) {
        return FermataLanguageValueEnglish;
    }

    // System default: detect preferred language
    for (NSString *lang in [NSLocale preferredLanguages]) {
        if ([lang hasPrefix:@"ja"]) {
            return FermataLanguageValueJapanese;
        }
        if ([lang hasPrefix:@"en"]) {
            return FermataLanguageValueEnglish;
        }
    }

    return FermataLanguageValueEnglish;
}


NSString *FermataLocalizedString(NSString *key)
{
    static NSDictionary<NSString *, NSString *> *enStrings = nil;
    static NSDictionary<NSString *, NSString *> *jaStrings = nil;
    static dispatch_once_t onceToken;

    dispatch_once(&onceToken, ^{
        enStrings = @{
            @"menu.prevent":              @"Prevent Lid Close Sleep",
            @"menu.postpone":             @"Postpone Lid Close Sleep",
            @"menu.settings":             @"Settings…",
            @"menu.about":                @"About Fermata",
            @"menu.quit":                 @"Quit Fermata",

            @"prefs.title":               @"Settings",
            @"prefs.auto_header":         @"Automatically prevent Lid Close Sleep when:",
            @"prefs.action.idle_sleep":   @"is preventing Idle Sleep",
            @"prefs.action.running":      @"is running",
            @"prefs.add_app":             @"Add Application…",
            @"prefs.remove_app":          @"Remove Application",
            @"prefs.update_freq":         @"Update frequency:",
            @"prefs.reenable_delay":      @"Delay before re-enabling:",
            @"prefs.manual_duration":     @"Manual activation duration:",
            @"prefs.also_prevent":        @"When activated, also prevent:",
            @"prefs.disk_sleep":          @"Disk Sleep",
            @"prefs.display_sleep":       @"Display Sleep",
            @"prefs.language":            @"Language:",
            @"prefs.lang.system":         @"System Default",
            @"prefs.lang.en":             @"English",
            @"prefs.lang.ja":             @"日本語",
            @"prefs.launch_at_login":     @"Launch Fermata at login",

            @"duration.none":             @"None",
            @"duration.forever":          @"Forever",
            @"duration.1s":               @"1 second",
            @"duration.5s":               @"5 seconds",
            @"duration.10s":              @"10 seconds",
            @"duration.15s":              @"15 seconds",
            @"duration.30s":              @"30 seconds",
            @"duration.1m":               @"1 minute",
            @"duration.5m":               @"5 minutes",
            @"duration.10m":              @"10 minutes",
            @"duration.15m":              @"15 minutes",
            @"duration.30m":              @"30 minutes",

            @"alert.helper_missing.title": @"Privileged Helper Not Installed",
            @"alert.helper_missing.body":  @"Fermata needs its privileged helper to control lid-close sleep.\n\nIf you are using an ad-hoc / unsigned build, run Scripts/install-helper.sh in Terminal once, then try again.",
            @"alert.login_item.failed":    @"Couldn't add Fermata to Login Items list."
        };

        jaStrings = @{
            @"menu.prevent":              @"蓋閉じスリープを無効にする",
            @"menu.postpone":             @"蓋閉じスリープを一時的に無効にする",
            @"menu.settings":             @"設定…",
            @"menu.about":                @"Fermata について",
            @"menu.quit":                 @"Fermata を終了",

            @"prefs.title":               @"設定",
            @"prefs.auto_header":         @"以下の条件で自動的に蓋閉じスリープを無効にする:",
            @"prefs.action.idle_sleep":   @"アイドルスリープ阻害中",
            @"prefs.action.running":      @"起動中",
            @"prefs.add_app":             @"アプリを追加…",
            @"prefs.remove_app":          @"アプリを削除",
            @"prefs.update_freq":         @"監視間隔:",
            @"prefs.reenable_delay":      @"スリープ再開までの猶予:",
            @"prefs.manual_duration":     @"手動有効化の持続時間:",
            @"prefs.also_prevent":        @"有効時に併せて無効にする:",
            @"prefs.disk_sleep":          @"ディスクのスリープ",
            @"prefs.display_sleep":       @"ディスプレイのスリープ",
            @"prefs.language":            @"言語:",
            @"prefs.lang.system":         @"システム設定に従う",
            @"prefs.lang.en":             @"English",
            @"prefs.lang.ja":             @"日本語",
            @"prefs.launch_at_login":     @"ログイン時に Fermata を起動",

            @"duration.none":             @"なし",
            @"duration.forever":          @"無制限",
            @"duration.1s":               @"1秒",
            @"duration.5s":               @"5秒",
            @"duration.10s":              @"10秒",
            @"duration.15s":              @"15秒",
            @"duration.30s":              @"30秒",
            @"duration.1m":               @"1分",
            @"duration.5m":               @"5分",
            @"duration.10m":              @"10分",
            @"duration.15m":              @"15分",
            @"duration.30m":              @"30分",

            @"alert.helper_missing.title": @"特権ヘルパーが未登録です",
            @"alert.helper_missing.body":  @"蓋閉じスリープを制御するには特権ヘルパーの登録が必要です。\n\n無料（未署名）ビルドをお使いの場合は、ターミナルで Scripts/install-helper.sh を 1 回実行してから再度お試しください。",
            @"alert.login_item.failed":    @"ログイン項目に Fermata を追加できませんでした。"
        };
    });

    NSString *lang = FermataCurrentLanguageCode();
    NSDictionary<NSString *, NSString *> *table = [lang isEqualToString:FermataLanguageValueJapanese] ? jaStrings : enStrings;

    NSString *value = table[key];
    if (value) return value;

    value = enStrings[key];
    return value ?: key;
}
