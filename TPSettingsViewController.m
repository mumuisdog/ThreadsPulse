#import "TPSettingsViewController.h"
#import "TPPrefs.h"
#import "TPDownloader.h"
#import "TPLocalization.h"
#import "TPHUD.h"
#import "TPUI.h"
#import <SafariServices/SafariServices.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#import "TPVersion.h"
static NSString *const kTPDonateURL = @"https://ko-fi.com/mumuisdog";

#pragma mark - 樣式（F：霧面卡片）

static UIColor *TPDyn(UIColor *light, UIColor *dark) {
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *t) {
        return t.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light;
    }];
}
/// 頁面底色：深色接近 Threads 的 #101010
static UIColor *TPPageColor(void) {
    return TPDyn([UIColor colorWithWhite:0.96 alpha:1], [UIColor colorWithWhite:0.063 alpha:1]);
}
/// 霧面卡片底色：半透明白（深色）／半透明黑（淺色）
static UIColor *TPCardColor(void) {
    return TPDyn([UIColor colorWithWhite:1 alpha:0.85], [UIColor colorWithWhite:1 alpha:0.08]);
}
static UIColor *TPHairlineColor(void) {
    return TPDyn([UIColor colorWithWhite:0 alpha:0.08], [UIColor colorWithWhite:1 alpha:0.10]);
}
static UIColor *TPKofiColor(void) {
    return [UIColor colorWithRed:1.00 green:0.37 blue:0.36 alpha:1];
}
/// 主題色（開關、分段選中、完成按鈕、操作文字），依「主題配色」設定
static UIColor *TPAccent(void) { return [TPUI accent]; }
/// 圖示用的主題色：深色模式稍亮，淺色模式稍深，兩邊都清楚
static UIColor *TPAccentIcon(void) { return [TPUI accentIcon]; }

/// 細線條圖示（顏色由主題色決定）
static UIImage *TPLineIcon(NSString *symbol) {
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:17 weight:UIImageSymbolWeightRegular];
    return [UIImage systemImageNamed:symbol withConfiguration:cfg] ?: [UIImage systemImageNamed:@"circle" withConfiguration:cfg];
}

static void TPApplyIcon(UIListContentConfiguration *c, NSString *symbol, UIColor *tint) {
    c.image = TPLineIcon(symbol);
    c.imageProperties.tintColor = tint ?: TPAccentIcon();
    c.imageProperties.reservedLayoutSize = CGSizeMake(26, 26);
    c.imageToTextPadding = 12;
}

/// 卡片底：半透明霧面
static void TPApplyCardBackground(UITableViewCell *cell) {
    UIBackgroundConfiguration *bg = [UIBackgroundConfiguration listGroupedCellConfiguration];
    bg.backgroundColor = TPCardColor();
    cell.backgroundConfiguration = bg;
}

/// 「串文時間格式」的範例：以 3 小時前的時間示範三種顯示方式
static NSString *TPTimePreview(NSInteger mode) {
    NSDate *sample = [NSDate dateWithTimeIntervalSinceNow:-3 * 3600 - 17 * 60 - 42];
    NSString *text;
    if (mode == 0) {
        // 用 Threads 自己的相對時間方法（NSDate+RelativeDate），範例才會和串文上的寫法一致，例如「3小時」。
        // 此時設定已是「相對時間」，插件的精確時間 hook 會直接放行原本的結果。
        SEL sel = NSSelectorFromString(@"shortenedFormattedDateRelativeToNow");
        id r = nil;
        if ([sample respondsToSelector:sel]) {
            @try { r = [sample valueForKey:@"shortenedFormattedDateRelativeToNow"]; } @catch (__unused id e) {}
        }
        text = [r isKindOfClass:[NSString class]] && [(NSString *)r length] ? r : TPL(@"3h");
    } else {
        NSDateFormatter *f = [NSDateFormatter new];
        f.locale = NSLocale.autoupdatingCurrentLocale;
        [f setLocalizedDateFormatFromTemplate:(mode == 1 ? @"MMMd HHmm" : @"yMMMd HHmmss")];
        text = [f stringFromDate:sample];
    }
    return [NSString stringWithFormat:TPL(@"Example: %@"), text];
}

#pragma mark - 頂部狀態卡

/// 最上方的狀態卡：Pulse 圖示、版本號、運作中・已開啟幾項功能
@interface TPSettingsHeaderView : UIView
- (void)setEnabledCount:(NSInteger)count;
@end

@implementation TPSettingsHeaderView {
    UIView *_card;
    CAGradientLayer *_gradient;
    UIView *_badge;
    UIImageView *_glyph;
    UILabel *_title;
    UILabel *_subtitle;
    UIView *_dot;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        UIColor *accent = TPAccent();
        _card = [UIView new];
        _card.layer.cornerRadius = 18;
        _card.layer.cornerCurve = kCACornerCurveContinuous;
        _card.layer.borderWidth = 1;
        _card.layer.borderColor = [accent colorWithAlphaComponent:0.35].CGColor;
        _card.clipsToBounds = YES;
        _gradient = [CAGradientLayer layer];
        _gradient.colors = @[(id)[accent colorWithAlphaComponent:0.28].CGColor, (id)[accent colorWithAlphaComponent:0.07].CGColor];
        _gradient.startPoint = CGPointMake(0, 0);
        _gradient.endPoint = CGPointMake(1, 1);
        [_card.layer addSublayer:_gradient];
        [self addSubview:_card];

        _badge = [UIView new];
        _badge.backgroundColor = accent;
        _badge.layer.cornerRadius = 12;
        _badge.layer.cornerCurve = kCACornerCurveContinuous;
        [_card addSubview:_badge];

        _glyph = [[UIImageView alloc] initWithImage:
                  [UIImage systemImageNamed:@"waveform.path.ecg"
                          withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:21 weight:UIImageSymbolWeightSemibold]]];
        _glyph.tintColor = UIColor.whiteColor;
        _glyph.contentMode = UIViewContentModeCenter;
        [_badge addSubview:_glyph];

        _title = [UILabel new];
        NSMutableAttributedString *t = [[NSMutableAttributedString alloc] initWithString:@"ThreadsPulse"
            attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:18 weight:UIFontWeightBold], NSForegroundColorAttributeName: UIColor.labelColor }];
        [t appendAttributedString:[[NSAttributedString alloc] initWithString:[@"  " stringByAppendingString:TP_VERSION]
            attributes:@{ NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightMedium], NSForegroundColorAttributeName: TPAccentIcon() }]];
        _title.attributedText = t;
        [_card addSubview:_title];

        _dot = [UIView new];
        _dot.backgroundColor = UIColor.systemGreenColor;
        _dot.layer.cornerRadius = 3.5;
        [_card addSubview:_dot];

        _subtitle = [UILabel new];
        _subtitle.font = [UIFont systemFontOfSize:13 weight:UIFontWeightRegular];
        _subtitle.textColor = UIColor.secondaryLabelColor;
        [_card addSubview:_subtitle];
    }
    return self;
}

- (void)setEnabledCount:(NSInteger)count {
    _subtitle.text = [NSString stringWithFormat:TPL(@"Running · %ld features on"), (long)count];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, inset = 16, d = 46;
    _card.frame = CGRectMake(inset, 6, w - inset * 2, self.bounds.size.height - 12);
    _gradient.frame = _card.bounds;
    CGFloat h = _card.bounds.size.height;
    _badge.frame = CGRectMake(14, (h - d) / 2, d, d);
    _glyph.frame = _badge.bounds;
    CGFloat x = CGRectGetMaxX(_badge.frame) + 12, tw = _card.bounds.size.width - x - 14;
    _title.frame = CGRectMake(x, h / 2 - 23, tw, 24);
    _dot.frame = CGRectMake(x, h / 2 + 8, 7, 7);
    _subtitle.frame = CGRectMake(x + 13, h / 2 + 2, tw - 13, 18);
}
@end

#pragma mark - 設定頁

@interface TPSettingsViewController () <UIDocumentPickerDelegate>
@end

@implementation TPSettingsViewController {
    NSArray<NSDictionary *> *_sections;
    CGFloat _headerWidth;
    UIButton *_doneButton;
    TPSettingsHeaderView *_header;
}

+ (void)present {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = TPTopViewController();
        if (!top) return;
        if ([top isKindOfClass:[UINavigationController class]] &&
            [[(UINavigationController *)top viewControllers].firstObject isKindOfClass:self]) return; // 已開啟
        TPSettingsViewController *vc = [[self alloc] initWithStyle:UITableViewStyleInsetGrouped];
        UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
        nav.modalPresentationStyle = UIModalPresentationPageSheet;
        nav.navigationBar.tintColor = TPAccent();
        nav.view.tintColor = TPAccent();
        if (@available(iOS 15.0, *)) {
            nav.sheetPresentationController.detents = @[UISheetPresentationControllerDetent.largeDetent];
            nav.sheetPresentationController.prefersGrabberVisible = YES;
        }
        [top presentViewController:nav animated:YES completion:nil];
    });
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationItem.title = nil;
    // 完成按鈕：明確指定顏色，不沿用 Threads 的全域色調（深色模式下是黑色，看不清楚）
    // Threads 會用全域外觀改掉導覽列按鈕的顏色（淺色模式甚至看不見），所以自己畫：主題色圓底＋白色勾勾，圖片固定顏色不受影響
    UIButton *doneButton = [UIButton buttonWithType:UIButtonTypeCustom];
    _doneButton = doneButton;
    doneButton.frame = CGRectMake(0, 0, 32, 32);
    doneButton.backgroundColor = TPAccent();
    doneButton.layer.cornerRadius = 16;
    UIImage *check = [[UIImage systemImageNamed:@"checkmark"
                               withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightBold]]
                      imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
    [doneButton setImage:check forState:UIControlStateNormal];
    doneButton.accessibilityLabel = TPL(@"Done");
    [doneButton addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [doneButton.widthAnchor constraintEqualToConstant:32].active = YES;
    [doneButton.heightAnchor constraintEqualToConstant:32].active = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:doneButton];
    self.navigationController.navigationBar.tintColor = TPAccent();
    self.view.tintColor = TPAccent();
    self.tableView.backgroundColor = TPPageColor();
    self.tableView.separatorColor = TPHairlineColor();
    self.tableView.sectionHeaderTopPadding = 6;

    // TP_MODEL_BEGIN — 這裡的文字都是「英文 key」，顯示時才經 TPL() 轉成目前語系
    _sections = @[
        @{ @"header": @"Ads & Privacy",
           @"footer": @"Turning ad blocking on or off takes effect after refreshing the feed or restarting the app.",
           @"rows": @[
               @{ @"type": @"switch", @"key": TPKeyBlockAds, @"title": @"Block Ads",
                  @"detail": @"Hide sponsored posts in the feed",
                  @"icon": @"shield" },
               @{ @"type": @"switch", @"key": TPKeyBlockScreenshotDetect, @"title": @"Block Screenshot Detection",
                  @"detail": @"Threads won't know when you take a screenshot or record the screen",
                  @"icon": @"camera.viewfinder" },
               @{ @"type": @"switch", @"key": TPKeyBlockAnalytics, @"title": @"Block Analytics",
                  @"detail": @"Stop Threads from sending usage data such as what you view, how long you stay and what you tap. Recommendations may become less accurate",
                  @"icon": @"eye.slash" },
               @{ @"type": @"switch", @"key": TPKeyStripTracking, @"title": @"Remove URL Tracking",
                  @"detail": @"Automatically strip xmt, igshid, utm_* and more when copying, sharing or opening links",
                  @"icon": @"scissors" },
           ]},
        @{ @"header": @"Download",
           @"footer": @"If the original size isn't available, the regular size is downloaded.\nTo save a profile picture, long-press it on a profile, or open it full screen and tap ↓ in the bottom-right corner.",
           @"rows": @[
               @{ @"type": @"switch", @"key": TPKeyShowDownloadBtn, @"title": @"Download Button",
                  @"detail": @"Long-press: choose photos or videos only\nTap: download all photos and videos",
                  @"icon": @"arrow.down.circle" },
               @{ @"type": @"switch", @"key": TPKeyOriginalImage, @"title": @"Download Original Size",
                  @"detail": @"Fetch the highest resolution from the web version",
                  @"icon": @"photo" },
               @{ @"type": @"switch", @"key": TPKeyOriginalAvatar, @"title": @"Download Original Profile Pictures",
                  @"detail": @"Long-press a profile picture on a profile to save it",
                  @"icon": @"person.crop.circle" },
           ]},
        @{ @"header": @"Video",
           @"footer": @"Videos play at this speed by default, and return to it after you let go of a long-press 2x.",
           @"rows": @[
               @{ @"type": @"switch", @"key": TPKeyNoAutoplay, @"title": @"Disable Autoplay",
                  @"detail": @"Videos in the feed won't play until you tap them",
                  @"icon": @"play.slash" },
               @{ @"type": @"segment", @"key": TPKeyPlaySpeed, @"title": @"Default Playback Speed", @"detail": @"",
                  @"icon": @"speedometer",
                  @"segments": @[@"1x", @"1.25x", @"1.5x", @"2x"] },
           ]},
        @{ @"header": @"Home Feed",
           @"footer": @"With everything here turned on, new posts only load after you fully close and reopen Threads.",
           @"rows": @[
               @{ @"type": @"switch", @"key": TPKeyKeepFeed, @"title": @"Keep Feed Position",
                  @"detail": @"Coming back from the background won't refresh the home feed, jump to the top or switch tabs",
                  @"icon": @"pin" },
               @{ @"type": @"segment", @"key": TPKeyKeepFeedLimit, @"title": @"Keep For", @"detail": @"",
                  @"icon": @"timer",
                  @"segments": @[@"10 min", @"30 min", @"No Limit"], @"showIf": @[TPKeyKeepFeed, @1],
                  @"note": @"If you're away longer than this, the feed refreshes as usual" },
               @{ @"type": @"switch", @"key": TPKeyNoPullRefresh, @"title": @"Disable Pull to Refresh",
                  @"detail": @"Pulling down at the top of the home feed won't refresh it, and the feed stops at the top without bouncing",
                  @"icon": @"arrow.down.to.line" },
               @{ @"type": @"caption", @"title": @"When Tapping the Home Tab" },
               @{ @"type": @"switch", @"key": TPKeyTabNoScrollTop, @"title": @"Don't Scroll to Top",
                  @"detail": @"When you're scrolled down the home feed, tapping the Home tab won't jump back to the top, so you stay where you were",
                  @"icon": @"arrow.up.to.line" },
               @{ @"type": @"switch", @"key": TPKeyTabNoRefresh, @"title": @"Don't Refresh",
                  @"detail": @"When you're already at the top of the home feed, tapping the Home tab won't refresh or load new posts",
                  @"icon": @"arrow.clockwise" },
           ]},
        @{ @"header": @"Hidden Items",
           @"rows": @[
               @{ @"type": @"switch", @"key": TPKeyHideFollowSuggest, @"title": @"Hide Follow Suggestions",
                  @"detail": @"Stop the follow suggestions sheet from popping up",
                  @"icon": @"person.crop.circle.badge.xmark" },
               @{ @"type": @"switch", @"key": TPKeyHideIGButton, @"title": @"Hide Instagram Button",
                  @"detail": @"Hide the Instagram button at the top of profiles",
                  @"icon": @"minus.square" },
               @{ @"type": @"switch", @"key": TPKeyHideFeedSuggest, @"title": @"Hide Suggested Accounts in Feed",
                  @"detail": @"Hide suggested-account cards in the feed, and the \"Suggested for you\" section on profiles and after you follow someone",
                  @"icon": @"person.badge.minus" },
           ]},
        @{ @"header": @"Links",
           @"footer": @"Auto-open reads the clipboard directly. If iOS asks to allow pasting every time, go to Settings › Threads › Paste from Other Apps and choose Allow.",
           @"footerIf": @[@[TPKeyClipboardLinks, @1], @[TPKeyClipboardMode, @1]],
           @"rows": @[
               @{ @"type": @"switch", @"key": TPKeyClipboardLinks, @"title": @"Detect Copied Links",
                  @"detail": @"When you come back or switch accounts, detect a copied Threads link and open it",
                  @"icon": @"doc.on.clipboard" },
               @{ @"type": @"segment", @"key": TPKeyClipboardMode, @"title": @"When a Link Is Found", @"detail": @"",
                  @"icon": @"hand.tap",
                  @"segments": @[@"Ask", @"Auto-open"], @"showIf": @[TPKeyClipboardLinks, @1] },
               @{ @"type": @"segment", @"key": TPKeyBannerPosition, @"title": @"Prompt Position", @"detail": @"",
                  @"icon": @"rectangle.topthird.inset.filled",
                  @"segments": @[@"Top", @"Middle", @"Bottom"], @"showIf": @[@[TPKeyClipboardLinks, @1], @[TPKeyClipboardMode, @0]] },
               @{ @"type": @"switch", @"key": TPKeyExternalBrowser, @"title": @"Open Links in External Browser",
                  @"detail": @"Links in posts and bios open in Safari (or your default browser) instead of the in-app browser. Threads links still open in the app",
                  @"icon": @"safari" },
           ]},
        @{ @"header": @"Interface & Interactions",
           @"rows": @[
               @{ @"type": @"theme", @"title": @"Theme Color", @"icon": @"paintpalette" },
               @{ @"type": @"switch", @"key": TPKeyConfirmLike, @"title": @"Like Confirmation",
                  @"detail": @"Ask before a like is sent, to prevent accidental taps. Removing a like won't ask.",
                  @"icon": @"heart" },
               @{ @"type": @"segment", @"key": TPKeyExactTime, @"title": @"Post Time Format", @"detail": @"",
                  @"icon": @"clock",
                  @"segments": @[@"Relative", @"Date & Time", @"With Seconds"], @"preview": @"time" },
               @{ @"type": @"switch", @"key": TPKeyPinTabBar, @"title": @"Keep Tab Bar Visible",
                  @"detail": @"Scrolling won't hide the tab bar at the bottom; it always stays on screen",
                  @"icon": @"dock.rectangle" },
               @{ @"type": @"switch", @"key": TPKeyCopyProfile, @"title": @"Copy Profile Info",
                  @"detail": @"On a profile, long-press the name, username, bio or profile picture to copy the name, username or bio",
                  @"icon": @"doc.on.doc" },
               @{ @"type": @"switch", @"key": TPKeyHomeLongPress, @"title": @"Long-Press Home Tab for Settings",
                  @"detail": @"Long-pressing the Home tab at the bottom opens ThreadsPulse settings instead",
                  @"icon": @"hand.point.up.left" },
           ]},
        @{ @"header": @"Backup",
           @"footer": @"Export your settings to a file, and import it after reinstalling or on another device.",
           @"rows": @[
               @{ @"type": @"action", @"action": @"export", @"title": @"Export Settings", @"detail": @"",
                  @"icon": @"square.and.arrow.up" },
               @{ @"type": @"action", @"action": @"import", @"title": @"Import Settings", @"detail": @"",
                  @"icon": @"square.and.arrow.down" },
           ]},
        @{ @"header": @"Advanced",
           @"rows": @[
               @{ @"type": @"switch", @"key": TPKeyDebugToast, @"title": @"Debug Hints",
                  @"detail": @"Turn on when a feature stops working. Hints show which features are active, to help report problems.",
                  @"icon": @"ladybug" },
               @{ @"type": @"switch", @"key": TPKeySideloadFix, @"title": @"Sideload Compatibility Fix",
                  @"detail": @"Keeps you signed in and app group data working after re-signing. Only active on re-signed apps; takes effect after reopening Threads",
                  @"icon": @"key" },
           ]},
        @{ @"header": @"Donate",
           @"footer": @"Your support keeps ThreadsPulse updated. Thank you!",
           @"rows": @[
               @{ @"type": @"link", @"url": kTPDonateURL, @"title": @"Buy Me a Coffee",
                  @"detail": @"Support ThreadsPulse on Ko-fi",
                  @"icon": @"cup.and.saucer.fill" },
           ]},
    ];
    // TP_MODEL_END
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.tableView.bounds.size.width;
    if (w > 0 && w != _headerWidth) {          // 寬度改變才重設，避免無限重排
        _headerWidth = w;
        _header = [[TPSettingsHeaderView alloc] initWithFrame:CGRectMake(0, 0, w, 92)];
        [_header setEnabledCount:[self enabledFeatureCount]];
        self.tableView.tableHeaderView = _header;
    }
}

- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }

/// 已開啟的功能數（所有開關，不含「除錯提示」）
- (NSInteger)enabledFeatureCount {
    NSInteger n = 0;
    for (NSDictionary *sec in _sections)
        for (NSDictionary *row in sec[@"rows"])
            if ([row[@"type"] isEqualToString:@"switch"] && ![row[@"key"] isEqualToString:TPKeyDebugToast]
                && [TPPrefs boolForKey:row[@"key"]]) n++;
    return n;
}

/// 換主題後：重畫狀態卡、完成按鈕和所有列
- (void)applyTheme {
    self.navigationController.navigationBar.tintColor = TPAccent();
    self.navigationController.view.tintColor = TPAccent();
    self.view.tintColor = TPAccent();
    _doneButton.backgroundColor = TPAccent();
    _headerWidth = 0;
    [self.view setNeedsLayout];
    [self.tableView reloadData];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return _sections.count + 1; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    return s < (NSInteger)_sections.count ? [self visibleRowsInSection:s].count : 2;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return TPL(s < (NSInteger)_sections.count ? _sections[s][@"header"] : @"About");
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s >= (NSInteger)_sections.count) return @"Made by h4x_0x30vm";
    NSString *f = _sections[s][@"footer"];
    if (!TPConditionMet(_sections[s][@"footerIf"])) return nil;
    return f.length ? TPL(f) : nil;
}

/// 條件格式：@[key, 值]，或多個條件 @[@[key, 值], @[key, 值]]（全部成立才算）
static NSArray<NSArray *> *TPConditions(NSArray *cond) {
    if (cond.count == 2 && [cond[0] isKindOfClass:[NSString class]]) return @[cond];
    return cond ?: @[];
}
static BOOL TPConditionMet(NSArray *cond) {
    for (NSArray *c in TPConditions(cond))
        if ([TPPrefs integerForKey:c[0]] != [c[1] integerValue]) return NO;
    return YES;
}
static BOOL TPConditionUsesKey(NSArray *cond, NSString *key) {
    for (NSArray *c in TPConditions(cond)) if ([c[0] isEqualToString:key]) return YES;
    return NO;
}

/// 這個區塊目前要顯示的列（有 showIf 的列，只在條件成立時顯示）
- (NSArray<NSDictionary *> *)visibleRowsInSection:(NSInteger)s {
    NSMutableArray *out = [NSMutableArray array];
    for (NSDictionary *row in _sections[s][@"rows"]) {
        if (!TPConditionMet(row[@"showIf"])) continue;
        [out addObject:row];
    }
    return out;
}

- (NSDictionary *)rowAt:(NSIndexPath *)ip { return [self visibleRowsInSection:ip.section][ip.row]; }

/// 某個設定改變後，依賴它的列要顯示或隱藏（例如「提示位置」只在「詢問」時出現）
- (void)refreshConditionalRowsForKey:(NSString *)key {
    for (NSInteger sec = 0; sec < (NSInteger)_sections.count; sec++) {
        BOOL affected = TPConditionUsesKey(_sections[sec][@"footerIf"], key);
        for (NSDictionary *row in _sections[sec][@"rows"])
            if (TPConditionUsesKey(row[@"showIf"], key)) affected = YES;
        if (affected)
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:sec]
                          withRowAnimation:UITableViewRowAnimationFade];
    }
}

/// 區塊內的小標題（例如「點首頁標籤時」），對齊下面各列的標題
- (UITableViewCell *)captionCellForRow:(NSDictionary *)row {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    TPApplyCardBackground(cell);
    UILabel *l = [UILabel new];
    l.text = TPL(row[@"title"]);
    l.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    l.textColor = UIColor.secondaryLabelColor;
    l.translatesAutoresizingMaskIntoConstraints = NO;
    [cell.contentView addSubview:l];
    UILayoutGuide *m = cell.contentView.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [l.leadingAnchor constraintEqualToAnchor:m.leadingAnchor constant:38],
        [l.trailingAnchor constraintLessThanOrEqualToAnchor:m.trailingAnchor],
        [l.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],
        [l.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-4],
    ]];
    return cell;
}

/// 主題配色：標題＋目前主題名稱，下方一排色票
- (UITableViewCell *)themeCellForRow:(NSDictionary *)row {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    TPApplyCardBackground(cell);
    UIView *cv = cell.contentView;
    NSInteger cur = [TPPrefs integerForKey:TPKeyTheme];

    UIImageView *icon = [[UIImageView alloc] initWithImage:TPLineIcon(row[@"icon"])];
    icon.tintColor = TPAccentIcon();
    icon.contentMode = UIViewContentModeCenter;
    UILabel *title = [UILabel new];
    title.text = TPL(row[@"title"]);
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    title.textColor = UIColor.labelColor;
    UILabel *name = [UILabel new];
    name.text = TPL([TPUI themeNameAtIndex:cur]);
    name.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    name.textColor = TPAccentIcon();
    UIStackView *dots = [UIStackView new];
    dots.axis = UILayoutConstraintAxisHorizontal;
    dots.distribution = UIStackViewDistributionEqualSpacing;
    dots.alignment = UIStackViewAlignmentCenter;

    __weak typeof(self) weakSelf = self;
    for (NSInteger i = 0; i < [TPUI themeCount]; i++) {
        UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
        b.backgroundColor = [TPUI themeColorAtIndex:i];
        b.layer.cornerRadius = 15;
        b.accessibilityLabel = TPL([TPUI themeNameAtIndex:i]);
        if (i == cur) {
            b.layer.borderWidth = 2.5;
            b.layer.borderColor = UIColor.labelColor.CGColor;
            [b setImage:[[UIImage systemImageNamed:@"checkmark"
                                  withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:12 weight:UIImageSymbolWeightBold]]
                         imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal]
               forState:UIControlStateNormal];
        }
        [b.widthAnchor constraintEqualToConstant:30].active = YES;
        [b.heightAnchor constraintEqualToConstant:30].active = YES;
        [b addAction:[UIAction actionWithHandler:^(UIAction *a) {
            if ([TPPrefs integerForKey:TPKeyTheme] == i) return;
            [TPPrefs setInteger:i forKey:TPKeyTheme];
            [TPUI hapticLight];
            [[NSNotificationCenter defaultCenter] postNotificationName:TPThemeDidChangeNotification object:nil];
            [weakSelf applyTheme];
        }] forControlEvents:UIControlEventTouchUpInside];
        [dots addArrangedSubview:b];
    }
    for (UIView *v in @[icon, title, name, dots]) { v.translatesAutoresizingMaskIntoConstraints = NO; [cv addSubview:v]; }
    UILayoutGuide *m = cv.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
        [icon.widthAnchor constraintEqualToConstant:26],
        [icon.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12],
        [title.topAnchor constraintEqualToAnchor:cv.topAnchor constant:14],
        [name.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
        [name.firstBaselineAnchor constraintEqualToAnchor:title.firstBaselineAnchor],
        [name.leadingAnchor constraintGreaterThanOrEqualToAnchor:title.trailingAnchor constant:8],
        [dots.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:12],
        [dots.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [dots.trailingAnchor constraintEqualToAnchor:m.trailingAnchor constant:-4],
        [dots.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-14],
    ]];
    return cell;
}

/// F2 樣式：標題在上、分段按鈕在下，整列是一張霧面卡片
- (UITableViewCell *)segmentCellForRow:(NSDictionary *)row {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    TPApplyCardBackground(cell);
    UIView *cv = cell.contentView;

    UIImageView *icon = [[UIImageView alloc] initWithImage:TPLineIcon(row[@"icon"])];
    icon.tintColor = TPAccentIcon();
    icon.contentMode = UIViewContentModeCenter;
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    [cv addSubview:icon];

    UILabel *title = [UILabel new];
    title.text = TPL(row[@"title"]);
    title.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    title.textColor = UIColor.labelColor;
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [cv addSubview:title];

    NSArray<NSString *> *segs = row[@"segments"];
    NSMutableArray<NSString *> *labels = [NSMutableArray array];
    for (NSString *seg in segs) [labels addObject:TPL(seg)];
    UISegmentedControl *sc = [[UISegmentedControl alloc] initWithItems:labels];
    NSInteger cur = MAX(0, MIN([TPPrefs integerForKey:row[@"key"]], (NSInteger)segs.count - 1));
    sc.selectedSegmentIndex = cur;
    sc.backgroundColor = TPDyn([UIColor colorWithWhite:0 alpha:0.05], [UIColor colorWithWhite:1 alpha:0.06]);
    sc.selectedSegmentTintColor = TPAccent();
    [sc setTitleTextAttributes:@{ NSForegroundColorAttributeName: UIColor.secondaryLabelColor,
                                  NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightMedium] }
                      forState:UIControlStateNormal];
    [sc setTitleTextAttributes:@{ NSForegroundColorAttributeName: UIColor.whiteColor,
                                  NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold] }
                      forState:UIControlStateSelected];
    NSString *key = row[@"key"];
    UILabel *preview = nil;
    if ([row[@"preview"] isEqualToString:@"time"]) {
        preview = [UILabel new];
        preview.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightRegular];
        preview.textColor = UIColor.secondaryLabelColor;
        preview.text = TPTimePreview(cur);
        preview.translatesAutoresizingMaskIntoConstraints = NO;
        [cv addSubview:preview];
    }
    if (!preview && [row[@"note"] length]) {                 // 分段選項下方的固定說明
        preview = [UILabel new];
        preview.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        preview.textColor = UIColor.secondaryLabelColor;
        preview.numberOfLines = 0;
        preview.text = TPL(row[@"note"]);
        preview.translatesAutoresizingMaskIntoConstraints = NO;
        [cv addSubview:preview];
    }
    BOOL isTimePreview = [row[@"preview"] isEqualToString:@"time"];
    __weak UILabel *wp = isTimePreview ? preview : nil;
    __weak typeof(self) weakSelf = self;
    [sc addAction:[UIAction actionWithHandler:^(UIAction *a) {
        NSInteger idx = ((UISegmentedControl *)a.sender).selectedSegmentIndex;
        [TPPrefs setInteger:idx forKey:key];
        [TPUI hapticLight];
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf refreshConditionalRowsForKey:key]; });
        if (wp) {
            [UIView transitionWithView:wp duration:0.2 options:UIViewAnimationOptionTransitionCrossDissolve
                            animations:^{ wp.text = TPTimePreview(idx); } completion:nil];
        }
    }] forControlEvents:UIControlEventValueChanged];
    sc.translatesAutoresizingMaskIntoConstraints = NO;
    [cv addSubview:sc];

    UILayoutGuide *m = cv.layoutMarginsGuide;
    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
        [icon.widthAnchor constraintEqualToConstant:26],
        [icon.centerYAnchor constraintEqualToAnchor:title.centerYAnchor],
        [title.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:12],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:m.trailingAnchor],
        [title.topAnchor constraintEqualToAnchor:cv.topAnchor constant:14],
        [sc.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:12],
        [sc.leadingAnchor constraintEqualToAnchor:m.leadingAnchor],
        [sc.trailingAnchor constraintEqualToAnchor:m.trailingAnchor],
        [sc.heightAnchor constraintEqualToConstant:32],
    ]];
    if (preview) {
        [NSLayoutConstraint activateConstraints:@[
            [preview.topAnchor constraintEqualToAnchor:sc.bottomAnchor constant:10],
            [preview.leadingAnchor constraintEqualToAnchor:m.leadingAnchor constant:2],
            [preview.trailingAnchor constraintLessThanOrEqualToAnchor:m.trailingAnchor],
            [preview.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-14],
        ]];
    } else {
        [sc.bottomAnchor constraintEqualToAnchor:cv.bottomAnchor constant:-14].active = YES;
    }
    return cell;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];

    // ---- 關於 ----
    if (ip.section >= (NSInteger)_sections.count) {
        if (ip.row == 0) {
            UIListContentConfiguration *c = [UIListContentConfiguration valueCellConfiguration];
            c.text = TPL(@"Version");
            c.secondaryText = TP_VERSION;
            TPApplyIcon(c, @"info.circle", nil);
            cell.contentConfiguration = c;
            TPApplyCardBackground(cell);
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            UIListContentConfiguration *c = [UIListContentConfiguration cellConfiguration];
            c.text = TPL(@"Reset All Settings");
            c.textProperties.color = UIColor.systemRedColor;
            TPApplyIcon(c, @"arrow.counterclockwise", UIColor.systemRedColor);
            cell.contentConfiguration = c;
            TPApplyCardBackground(cell);
        }
        return cell;
    }

    NSDictionary *row = [self rowAt:ip];
    NSString *type = row[@"type"];
    if ([type isEqualToString:@"segment"]) return [self segmentCellForRow:row];
    if ([type isEqualToString:@"theme"])   return [self themeCellForRow:row];
    if ([type isEqualToString:@"caption"]) return [self captionCellForRow:row];
    NSString *detail = row[@"detail"];

    UIListContentConfiguration *c = detail.length ? [UIListContentConfiguration subtitleCellConfiguration]
                                                  : [UIListContentConfiguration cellConfiguration];
    c.text = TPL(row[@"title"]);
    if (detail.length) {
        c.secondaryText = TPL(detail);
        c.secondaryTextProperties.color = UIColor.secondaryLabelColor;
        c.secondaryTextProperties.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        c.textToSecondaryTextVerticalPadding = 3;
    }
    TPApplyIcon(c, row[@"icon"], nil);
    TPApplyCardBackground(cell);

    if ([type isEqualToString:@"switch"]) {
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        UISwitch *sw = [UISwitch new];
        sw.onTintColor = TPAccent();
        sw.on = [TPPrefs boolForKey:row[@"key"]];
        sw.tag = ip.section * 100 + ip.row;
        [sw addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
    } else if ([type isEqualToString:@"link"]) {
        UIBackgroundConfiguration *bg = [UIBackgroundConfiguration listGroupedCellConfiguration];
        bg.backgroundColor = [TPKofiColor() colorWithAlphaComponent:0.12];
        bg.strokeColor = [TPKofiColor() colorWithAlphaComponent:0.40];
        bg.strokeWidth = 0.5;
        cell.backgroundConfiguration = bg;
        c.imageProperties.tintColor = TPKofiColor();
        UIImageView *arrow = [[UIImageView alloc] initWithImage:
            [UIImage systemImageNamed:@"chevron.right"
                    withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightBold]]];
        arrow.tintColor = UIColor.tertiaryLabelColor;
        cell.accessoryView = arrow;
    }
    cell.contentConfiguration = c;
    return cell;
}

- (void)switchChanged:(UISwitch *)sw {
    NSInteger s = sw.tag / 100, r = sw.tag % 100;
    NSString *key = [self visibleRowsInSection:s][r][@"key"];
    [TPPrefs setBool:sw.on forKey:key];
    [TPUI hapticLight];
    [_header setEnabledCount:[self enabledFeatureCount]];
    dispatch_async(dispatch_get_main_queue(), ^{ [self refreshConditionalRowsForKey:key]; });
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    UITableViewCell *cell = [tv cellForRowAtIndexPath:ip];

    if (ip.section >= (NSInteger)_sections.count) {
        if (ip.row == 1) [self confirmReset];
        return;
    }
    NSDictionary *row = [self rowAt:ip];
    NSString *type = row[@"type"];
    if ([type isEqualToString:@"action"]) {
        if ([row[@"action"] isEqualToString:@"export"]) [self exportSettingsFrom:cell];
        else [self importSettings];
    } else if ([type isEqualToString:@"link"]) {
        [self openLink:row[@"url"]];
    }
}

#pragma mark - 贊助連結

- (void)openLink:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) return;
    SFSafariViewController *sf = [[SFSafariViewController alloc] initWithURL:url];
    sf.preferredControlTintColor = TPKofiColor();
    sf.dismissButtonStyle = SFSafariViewControllerDismissButtonStyleClose;
    [self presentViewController:sf animated:YES completion:nil];
}

#pragma mark - 重設

- (void)confirmReset {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:TPL(@"Reset All Settings?") message:nil
                                                        preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:TPL(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:TPL(@"Reset") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *x) {
        [TPPrefs resetAll];
        [[NSNotificationCenter defaultCenter] postNotificationName:TPThemeDidChangeNotification object:nil];
        [self applyTheme];
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

#pragma mark - 匯出／匯入

- (void)exportSettingsFrom:(UIView *)source {
    NSData *data = [TPPrefs exportJSONData];
    NSURL *file = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"ThreadsPulse-Settings.json"]];
    if (!data || ![data writeToURL:file atomically:YES]) {
        [TPHUD toast:TPL(@"Export failed")];
        return;
    }
    UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:@[file] applicationActivities:nil];
    av.popoverPresentationController.sourceView = source;
    av.popoverPresentationController.sourceRect = source.bounds;
    [self presentViewController:av animated:YES completion:nil];
}

- (void)importSettings {
    UIDocumentPickerViewController *picker =
        [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeJSON] asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSData *data = urls.firstObject ? [NSData dataWithContentsOfURL:urls.firstObject] : nil;
    NSInteger n = [TPPrefs importJSONData:data];
    // 匯入的設定可能換了主題：重畫整頁（含狀態卡的功能數），Pulse 入口也跟著變色
    [[NSNotificationCenter defaultCenter] postNotificationName:TPThemeDidChangeNotification object:nil];
    [self applyTheme];
    if (n < 0) { [TPUI hapticError];   [TPHUD toast:TPL(@"Invalid settings file")]; }
    else       { [TPUI hapticSuccess]; [TPHUD toast:[NSString stringWithFormat:TPL(@"Imported %ld settings"), (long)n]]; }
}
@end
