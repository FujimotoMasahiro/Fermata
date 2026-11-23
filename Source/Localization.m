// (c) 2026 Masahiro Fujimoto
// MIT License (or) 1-clause BSD License

#import "Localization.h"

NSString * const FermataLanguagePreferenceKey         = @"AppLanguage";
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
            // Menu items
            @"menu.prevent":              @"Prevent Lid Close Sleep",
            @"menu.postpone":             @"Postpone Lid Close Sleep",
            @"menu.settings":             @"Settings…",
            @"menu.about":                @"About Fermata",
            @"menu.quit":                 @"Quit Fermata",
            @"menu.status.active":        @"Status: Preventing Lid Close Sleep",
            @"menu.status.active_reason": @"Status: Active (%@)",
            @"menu.status.inactive":      @"Status: Normal Sleep",
            @"menu.status.manual":        @"Manual",

            // App runtime assertion status
            @"status.asserting":          @"Asserting power (preventing sleep)",
            @"status.running_idle":       @"Running (no power assertion)",
            @"status.not_running":        @"Not running",
            @"status.tooltip.asserting":  @"Active IOKit power assertions:\n%@",
            @"status.tooltip.idle":       @"App is running, but currently holds no idle/system sleep power assertion.",
            @"status.tooltip.not_running":@"App is not currently running.",

            // Menu tooltips
            @"tooltip.menu.lid_close":    @"Toggles macOS SleepDisabled via the privileged helper so your Mac stays awake even when the lid is closed. If a manual duration is set, it turns off automatically after that time.",
            @"tooltip.menu.settings":     @"Configure watched applications, polling intervals, additional sleep assertions, and display language.",
            @"tooltip.menu.about":        @"Show version and license information for Fermata.",
            @"tooltip.menu.quit":         @"Quit Fermata and immediately restore normal lid-close sleep (SleepDisabled = 0).",

            // Preferences UI labels
            @"prefs.title":               @"Settings",
            @"prefs.auto_header":         @"Automatically prevent Lid Close Sleep when:",
            @"prefs.action.idle_sleep":   @"is preventing Idle Sleep",
            @"prefs.action.running":      @"is running",
            @"prefs.add_app":             @"Add Application…",
            @"prefs.remove_app":          @"Remove Application",
            @"prefs.update_freq":         @"Check interval:",
            @"prefs.reenable_delay":      @"Delay before re-enabling:",
            @"prefs.manual_duration":     @"Manual activation duration:",
            @"prefs.also_prevent":        @"Additional options:",
            @"prefs.display_sleep":       @"Keep display awake",
            @"prefs.language":            @"Language:",
            @"prefs.lang.system":         @"System Default",
            @"prefs.lang.en":             @"English",
            @"prefs.lang.ja":             @"日本語",
            @"prefs.launch_at_login":     @"Launch Fermata at login",

            // Durations
            @"duration.none":             @"Immediately",
            @"duration.forever":          @"Indefinitely",
            @"duration.1s":               @"1 second",
            @"duration.5s":               @"5 seconds",
            @"duration.10s":              @"10 seconds",
            @"duration.15s":              @"15 seconds",
            @"duration.30s":              @"30 seconds",
            @"duration.5s_interval":      @"Every 5 seconds",
            @"duration.10s_interval":     @"Every 10 seconds",
            @"duration.15s_interval":     @"Every 15 seconds",
            @"duration.30s_interval":     @"Every 30 seconds",
            @"duration.1m":               @"1 minute",
            @"duration.5m":               @"5 minutes",
            @"duration.10m":              @"10 minutes",
            @"duration.15m":              @"15 minutes",
            @"duration.30m":              @"30 minutes",

            // Popover titles
            @"help.title.auto_list":       @"Watched Applications",
            @"help.title.update_freq":     @"Check Interval",
            @"help.title.reenable_delay":  @"Delay Before Re-enabling",
            @"help.title.manual_duration": @"Manual Activation Duration",
            @"help.title.display_sleep":   @"Keep Display Awake",
            @"help.title.language":        @"Display Language",
            @"help.title.launch_at_login": @"Launch at Login",

            // Help / tooltip descriptions (derived from source behavior)
            @"tooltip.auto_list":         @"Watches the listed applications and asks the privileged helper to set macOS SleepDisabled = true whenever any matching condition is met:\n\n• \"is preventing Idle Sleep\": Reads IOKit power assertions (IOPMCopyAssertionsByProcess) and activates only while the app holds an idle-sleep assertion (e.g., playing audio or running an active job).\n• \"is running\": Checks NSRunningApplication and stays active as long as the app is open.",
            @"tooltip.action_popup":      @"Choose when this app prevents lid-close sleep:\n• \"is preventing Idle Sleep\": Active only while the app holds an IOKit idle-sleep assertion.\n• \"is running\": Active whenever the app process is open.",
            @"tooltip.action.idle_sleep": @"Reads active IOKit power assertions (IOPMCopyAssertionsByProcess) and prevents lid-close sleep only while this app is preventing idle sleep.",
            @"tooltip.action.running":    @"Checks NSRunningApplication and prevents lid-close sleep for as long as this app is open.",
            @"tooltip.add_app":           @"Select a macOS application (.app) to add to the automatic watch list.",
            @"tooltip.remove_app":        @"Remove the currently selected application from the watch list.",
            @"tooltip.update_freq":       @"Interval for the background NSTimer that polls IOKit power assertions and checks manual timer expiration.\n\nShorter intervals react faster. Note that app launches and quits themselves are detected immediately via NSWorkspace notifications.",
            @"tooltip.reenable_delay":    @"Wait time before restoring normal lid-close sleep (SleepDisabled = false) after conditions are no longer met.\n\nPrevents sudden sleep during brief gaps such as track changes. If a condition becomes true again during the wait, re-enabling is canceled. Turning off manually takes effect immediately.",
            @"tooltip.manual_duration":   @"How long manual activation from the menu bar stays on before turning off automatically.\n\nWhen a duration is set, a remaining-time bar appears below the menu bar icon. Choose \"Indefinitely\" to keep it active until turned off manually.",
            @"tooltip.also_prevent":      @"Extra power option while Fermata is preventing lid-close sleep. System idle sleep (PreventUserIdleSystemSleep) is always prevented automatically while active.",
            @"tooltip.display_sleep":     @"When checked, holds IOKit assertion kIOPMAssertPreventUserIdleDisplaySleep while Fermata is active so the display will not turn off automatically.\n\nLeave this off to save battery when you only want background tasks to keep running.",
            @"tooltip.language":          @"Switches the display language of menus and settings immediately without restarting the app.\n\n\"System Default\" automatically follows macOS preferred languages.",
            @"tooltip.launch_at_login":   @"Registers Fermata in macOS Login Items (using SMAppService on macOS 13+) so it starts automatically when you log in.",

            // Alerts
            @"alert.helper_missing.title": @"Privileged Helper Not Installed",
            @"alert.helper_missing.body":  @"Fermata needs its privileged helper to control lid-close sleep.\n\nIf you are using an ad-hoc / unsigned build, run Scripts/install-helper.sh in Terminal once, then try again.",
            @"alert.login_item.failed":    @"Couldn't add Fermata to Login Items list."
        };

        jaStrings = @{
            // Menu items
            @"menu.prevent":              @"画面を閉じてもスリープしない",
            @"menu.postpone":             @"一時的にスリープを防ぐ",
            @"menu.settings":             @"設定…",
            @"menu.about":                @"Fermataについて",
            @"menu.quit":                 @"Fermataを終了",
            @"menu.status.active":        @"状態: スリープ防止中",
            @"menu.status.active_reason": @"状態: スリープ防止中（%@）",
            @"menu.status.inactive":      @"状態: 通常スリープ",
            @"menu.status.manual":        @"手動",

            // App runtime assertion status
            @"status.asserting":          @"電源アサーション中",
            @"status.running_idle":       @"起動中（アサーションなし）",
            @"status.not_running":        @"未起動",
            @"status.tooltip.asserting":  @"発行中の電源アサーション:\n%@",
            @"status.tooltip.idle":       @"アプリは起動中ですが、現在はスリープ防止の電源アサーションを出していません。",
            @"status.tooltip.not_running":@"現在このアプリは起動していません。",

            // Menu tooltips
            @"tooltip.menu.lid_close":    @"オンにすると特権ヘルパー経由で macOS の SleepDisabled を有効にし、MacBook の画面を閉じてもスリープしないようにします。「手動オンの持続時間」を設定している場合は、時間が経つと自動でオフに戻ります。",
            @"tooltip.menu.settings":     @"自動スリープ防止の対象アプリや確認間隔、あわせて防ぐスリープ、表示言語を設定します。",
            @"tooltip.menu.about":        @"Fermata のバージョンとライセンス情報を表示します。",
            @"tooltip.menu.quit":         @"Fermata を終了し、macOS のスリープ設定（SleepDisabled）を通常状態に戻します。",

            // Preferences UI labels
            @"prefs.title":               @"設定",
            @"prefs.auto_header":         @"次のアプリが動作中は画面を閉じてもスリープしない:",
            @"prefs.action.idle_sleep":   @"スリープ防止中のみ",
            @"prefs.action.running":      @"起動中は常に",
            @"prefs.add_app":             @"アプリを追加…",
            @"prefs.remove_app":          @"アプリを削除",
            @"prefs.update_freq":         @"状態の確認間隔:",
            @"prefs.reenable_delay":      @"スリープ許可までの待ち時間:",
            @"prefs.manual_duration":     @"手動オンの持続時間:",
            @"prefs.also_prevent":        @"追加オプション:",
            @"prefs.display_sleep":       @"画面を消灯させない",
            @"prefs.language":            @"表示言語:",
            @"prefs.lang.system":         @"システムに合わせる",
            @"prefs.lang.en":             @"English",
            @"prefs.lang.ja":             @"日本語",
            @"prefs.launch_at_login":     @"ログイン時に自動で起動する",

            // Durations
            @"duration.none":             @"すぐ戻す",
            @"duration.forever":          @"無期限",
            @"duration.1s":               @"1秒",
            @"duration.5s":               @"5秒",
            @"duration.10s":              @"10秒",
            @"duration.15s":              @"15秒",
            @"duration.30s":              @"30秒",
            @"duration.5s_interval":      @"5秒ごと",
            @"duration.10s_interval":     @"10秒ごと",
            @"duration.15s_interval":     @"15秒ごと",
            @"duration.30s_interval":     @"30秒ごと",
            @"duration.1m":               @"1分",
            @"duration.5m":               @"5分",
            @"duration.10m":              @"10分",
            @"duration.15m":              @"15分",
            @"duration.30m":              @"30分",

            // Popover titles
            @"help.title.auto_list":       @"自動スリープ防止の対象アプリ",
            @"help.title.update_freq":     @"状態の確認間隔",
            @"help.title.reenable_delay":  @"スリープ許可までの待ち時間",
            @"help.title.manual_duration": @"手動オンの持続時間",
            @"help.title.display_sleep":   @"画面を消灯させない",
            @"help.title.language":        @"表示言語",
            @"help.title.launch_at_login": @"ログイン時の自動起動",

            // Help / tooltip descriptions (derived from source behavior)
            @"tooltip.auto_list":         @"リストに登録したアプリを監視し、条件を満たす間だけ特権ヘルパー経由で macOS の SleepDisabled を有効にします。\n\n・「スリープ防止中のみ」: 再生や処理中など、アプリが macOS へ電源アサーション（IOPMCopyAssertionsByProcess）を出している間だけ有効にします。\n・「起動中は常に」: NSRunningApplication で起動状態を監視し、アプリが開いている間はずっと有効にします。",
            @"tooltip.action_popup":      @"このアプリでいつスリープを防ぐかを選びます。\n・「スリープ防止中のみ」: アプリがスリープ防止要求を出している処理中だけ有効にします。\n・「起動中は常に」: アプリが開いている間はずっと有効にします。",
            @"tooltip.action.idle_sleep": @"macOS の電源アサーション（IOPMCopyAssertionsByProcess）を監視し、このアプリがスリープを止めている処理中だけ画面閉じスリープを防ぎます。",
            @"tooltip.action.running":    @"アプリの起動状態（NSRunningApplication）を監視し、アプリが開いている間は常に画面閉じスリープを防ぎます。",
            @"tooltip.add_app":           @"自動スリープ防止の対象にするアプリ（.app）を選んでリストに追加します。",
            @"tooltip.remove_app":        @"リストで選択中のアプリを監視対象から削除します。",
            @"tooltip.update_freq":       @"対象アプリがスリープ防止要求を出しているかや、手動タイマーの期限切れをバックグラウンドのタイマー（NSTimer）で確認する間隔です。\n\n短いほど反応が速くなります。なお、アプリの起動・終了自体は macOS 通知（NSWorkspace）で即座に検知します。",
            @"tooltip.reenable_delay":    @"条件が外れてから、通常の「画面を閉じたらスリープ」へ戻す（SleepDisabled を解除する）までの待ち時間です。\n\n曲の切り替わりや一瞬の処理停止でスリープしてしまうのを防ぎます。待機中に再び条件を満たすと解除は取り消されます（手動オフ時は待たずにすぐ解除します）。",
            @"tooltip.manual_duration":   @"メニューバーから手動でオンにしたとき、自動でオフに戻るまでの時間です。\n\n時間を指定するとメニューバーアイコンの下に残り時間バーが表示され、経過後に通常スリープへ戻ります。「無期限」を選ぶと手動でオフにするまで継続します。",
            @"tooltip.also_prevent":      @"Fermata が画面閉じスリープを防いでいる間の追加オプションです（システム本体のアイドルスリープ防止は自動で有効になります）。",
            @"tooltip.display_sleep":     @"オンにすると、Fermata が有効なあいだ IOKit の kIOPMAssertPreventUserIdleDisplaySleep を発行し、操作していない間もディスプレイが消灯（スリープ）しないようにします。\n\nバッテリー消費を抑えたい場合はオフがおすすめです。",
            @"tooltip.language":          @"メニューや設定画面の表示言語を切り替えます（アプリの再起動は不要です）。\n\n「システムに合わせる」を選ぶと macOS の優先言語に自動で従います。",
            @"tooltip.launch_at_login":   @"オンにすると macOS のログイン項目（macOS 13 以降は SMAppService）に登録され、Mac にログインしたとき自動で Fermata が起動します。",

            // Alerts
            @"alert.helper_missing.title": @"特権ヘルパーが登録されていません",
            @"alert.helper_missing.body":  @"画面を閉じたときのスリープを制御するには、特権ヘルパーの登録が必要です。\n\n無料（未署名）ビルドをお使いの場合は、ターミナルで Scripts/install-helper.sh を 1 回実行してから再度お試しください。",
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
