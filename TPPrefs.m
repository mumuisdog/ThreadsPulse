#import "TPPrefs.h"
#import "TPVersion.h"

NSString *const TPKeyBlockAds        = @"tp_block_ads";
NSString *const TPKeyStripTracking   = @"tp_strip_tracking";
NSString *const TPKeyShowDownloadBtn = @"tp_show_download_btn";
NSString *const TPKeyDebugToast      = @"tp_debug_toast";
NSString *const TPKeyOriginalAvatar  = @"tp_original_avatar";
NSString *const TPKeyOriginalImage   = @"tp_original_image";
NSString *const TPKeyClipboardLinks  = @"tp_clipboard_links";
NSString *const TPKeyConfirmLike     = @"tp_confirm_like";
NSString *const TPKeyPlaySpeed       = @"tp_play_speed";
NSString *const TPKeyClipboardMode   = @"tp_clipboard_mode";
NSString *const TPKeyBannerPosition  = @"tp_banner_position";
NSString *const TPKeyExactTime       = @"tp_exact_time";
NSString *const TPKeyKeepFeed        = @"tp_keep_feed";
NSString *const TPKeyPinTabBar       = @"tp_pin_tab_bar";
NSString *const TPKeyCopyProfile     = @"tp_copy_profile";
NSString *const TPKeySideloadFix     = @"tp_sideload_fix";
NSString *const TPKeyBlockScreenshotDetect = @"tp_block_screenshot_detect";
NSString *const TPKeyBlockAnalytics  = @"tp_block_analytics";
NSString *const TPKeyExternalBrowser = @"tp_external_browser";
NSString *const TPKeyHideIGButton    = @"tp_hide_ig_button";
NSString *const TPKeyHomeLongPress   = @"tp_home_long_press";
NSString *const TPKeyTheme           = @"tp_theme";
NSString *const TPKeyHideFeedSuggest = @"tp_hide_feed_suggest";
NSString *const TPKeyNoAutoplay      = @"tp_no_autoplay";
NSString *const TPKeyHideFollowSuggest = @"tp_hide_follow_suggest";
NSString *const TPKeyKeepFeedLimit   = @"tp_keep_feed_limit";
NSString *const TPKeyNoPullRefresh   = @"tp_no_pull_refresh";
NSString *const TPKeyTabNoScrollTop  = @"tp_tab_no_scroll_top";
NSString *const TPKeyTabNoRefresh    = @"tp_tab_no_refresh";

static NSString *const kSuite = @"com.example.threadspulse";

static NSArray<NSString *> *TPBoolKeys(void) {
    return @[TPKeyBlockAds, TPKeyStripTracking, TPKeyShowDownloadBtn, TPKeyDebugToast,
             TPKeyOriginalImage, TPKeyOriginalAvatar, TPKeyClipboardLinks, TPKeyConfirmLike, TPKeyKeepFeed, TPKeyHideFollowSuggest, TPKeyPinTabBar, TPKeyCopyProfile, TPKeySideloadFix, TPKeyBlockScreenshotDetect, TPKeyBlockAnalytics, TPKeyExternalBrowser, TPKeyHideIGButton, TPKeyHomeLongPress, TPKeyHideFeedSuggest, TPKeyNoAutoplay,
             TPKeyNoPullRefresh, TPKeyTabNoScrollTop, TPKeyTabNoRefresh];
}
static NSArray<NSString *> *TPIntKeys(void) {
    return @[TPKeyPlaySpeed, TPKeyExactTime, TPKeyClipboardMode, TPKeyBannerPosition, TPKeyKeepFeedLimit, TPKeyTheme];
}
/// 各整數設定的合法範圍上限（含），匯入時用來擋掉不合理的值
static NSInteger TPIntMax(NSString *key) {
    if ([key isEqualToString:TPKeyPlaySpeed])   return 3;
    if ([key isEqualToString:TPKeyExactTime])   return 2;
    if ([key isEqualToString:TPKeyClipboardMode])  return 1;
    if ([key isEqualToString:TPKeyBannerPosition]) return 2;
    if ([key isEqualToString:TPKeyKeepFeedLimit])  return 2;
    if ([key isEqualToString:TPKeyTheme])          return 5;
    return 0;
}

@implementation TPPrefs

+ (NSUserDefaults *)defaults {
    static NSUserDefaults *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        d = [[NSUserDefaults alloc] initWithSuiteName:kSuite];
        [d registerDefaults:@{
            TPKeyBlockAds: @YES,        TPKeyStripTracking: @YES,   TPKeyShowDownloadBtn: @YES,
            TPKeyDebugToast: @NO,       TPKeyOriginalImage: @YES,
            TPKeyPlaySpeed: @0,
            TPKeyExactTime: @0,         TPKeyConfirmLike: @NO,      TPKeyOriginalAvatar: @YES,  TPKeyClipboardLinks: @NO,  TPKeyClipboardMode: @0,  TPKeyBannerPosition: @0,
            TPKeyHideFollowSuggest: @YES, TPKeyPinTabBar: @NO, TPKeyCopyProfile: @YES, TPKeySideloadFix: @YES, TPKeyBlockScreenshotDetect: @YES, TPKeyBlockAnalytics: @NO, TPKeyExternalBrowser: @NO, TPKeyHideIGButton: @NO, TPKeyHomeLongPress: @NO, TPKeyTheme: @0, TPKeyHideFeedSuggest: @YES, TPKeyNoAutoplay: @NO, TPKeyKeepFeed: @NO,         TPKeyKeepFeedLimit: @0,
            TPKeyNoPullRefresh: @NO,    TPKeyTabNoScrollTop: @NO,   TPKeyTabNoRefresh: @NO,
        }];
        // 清掉已移除功能留下的舊設定
        [d removeObjectForKey:@"tp_default_mute"];
        [d removeObjectForKey:@"tp_video_audio"];
        [d removeObjectForKey:@"tp_quality_highest"];
    });
    return d;
}

+ (BOOL)boolForKey:(NSString *)key { return [[self defaults] boolForKey:key]; }
+ (void)setBool:(BOOL)value forKey:(NSString *)key { [[self defaults] setBool:value forKey:key]; }
+ (NSInteger)integerForKey:(NSString *)key { return [[self defaults] integerForKey:key]; }
+ (void)setInteger:(NSInteger)value forKey:(NSString *)key { [[self defaults] setInteger:value forKey:key]; }

+ (void)resetAll {
    for (NSString *k in TPBoolKeys()) [[self defaults] removeObjectForKey:k];
    for (NSString *k in TPIntKeys())  [[self defaults] removeObjectForKey:k];
}

#pragma mark - 備份

+ (NSData *)exportJSONData {
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    for (NSString *k in TPBoolKeys()) settings[k] = @([self boolForKey:k]);
    for (NSString *k in TPIntKeys())  settings[k] = @([self integerForKey:k]);
    NSDictionary *root = @{ @"app": @"ThreadsPulse", @"version": TP_VERSION, @"settings": settings };
    return [NSJSONSerialization dataWithJSONObject:root
                                           options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                             error:nil];
}

+ (NSInteger)importJSONData:(NSData *)data {
    if (!data.length) return -1;
    id root = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![root isKindOfClass:[NSDictionary class]]) return -1;
    NSDictionary *settings = root[@"settings"];
    if (![settings isKindOfClass:[NSDictionary class]]) return -1;

    NSInteger applied = 0;
    for (NSString *k in TPBoolKeys()) {
        id v = settings[k];
        if ([v isKindOfClass:[NSNumber class]]) { [self setBool:[v boolValue] forKey:k]; applied++; }
    }
    for (NSString *k in TPIntKeys()) {
        id v = settings[k];
        if ([v isKindOfClass:[NSNumber class]]) {
            NSInteger n = [v integerValue];
            if (n >= 0 && n <= TPIntMax(k)) { [self setInteger:n forKey:k]; applied++; }
        }
    }
    return applied;
}
@end
