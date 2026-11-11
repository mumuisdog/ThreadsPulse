#import "TPUI.h"
#import "TPPrefs.h"
#import "TPLocalization.h"
#import "TPHUD.h"

UIWindow *TPKeyWindow(void) {
    UIWindow *fallback = nil;
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        if (scene.activationState != UISceneActivationStateForegroundActive) continue;
        for (UIWindow *w in ((UIWindowScene *)scene).windows) {
            if (w.isKeyWindow) return w;
            if (!fallback && !w.isHidden) fallback = w;
        }
    }
    return fallback;
}

UIViewController *TPTopViewController(void) {
    UIViewController *vc = TPKeyWindow().rootViewController;
    while (vc.presentedViewController) vc = vc.presentedViewController;
    return vc;
}

#pragma mark - TPMenuItem

@implementation TPMenuItem
+ (instancetype)itemWithTitle:(NSString *)title symbol:(NSString *)symbol handler:(void (^)(void))handler {
    TPMenuItem *i = [TPMenuItem new];
    i.title = title; i.symbol = symbol; i.handler = handler;
    return i;
}
@end

/// 長按手勢：把選單項目掛在手勢上，觸發時跳出底部選單
@interface TPLongPressMenuGesture : UILongPressGestureRecognizer
@property (nonatomic, copy) NSArray<TPMenuItem *> *items;
@end
@implementation TPLongPressMenuGesture
@end

#pragma mark - TPUI

NSString *const TPThemeDidChangeNotification = @"TPThemeDidChangeNotification";

@implementation TPUI

// 主題：{主色, 圖示亮色（深色模式）, 圖示深色（淺色模式）, 名稱}
typedef struct { uint32_t main, iconDark, iconLight; const char *name; } TPTheme;
static const TPTheme kTPThemes[] = {
    { 0xD85A30, 0xF0997B, 0xC44F28, "Coral" },
    { 0x2F7BEA, 0x7FB2FF, 0x1F63C9, "Ocean" },
    { 0x1FA971, 0x6FD9A8, 0x168A5B, "Mint" },
    { 0x8A5CF5, 0xB9A0FF, 0x7046D9, "Lavender" },
    { 0xE0457B, 0xFF95B8, 0xC2335F, "Sakura" },
    { 0xE08A00, 0xFFC15A, 0xB86F00, "Amber" },
};
static UIColor *TPHex(uint32_t v) {
    return [UIColor colorWithRed:((v >> 16) & 0xFF) / 255.0 green:((v >> 8) & 0xFF) / 255.0 blue:(v & 0xFF) / 255.0 alpha:1];
}
static const TPTheme *TPCurrentTheme(void) {
    NSInteger i = [TPPrefs integerForKey:TPKeyTheme];
    if (i < 0 || i >= (NSInteger)(sizeof(kTPThemes) / sizeof(kTPThemes[0]))) i = 0;
    return &kTPThemes[i];
}
+ (NSInteger)themeCount { return sizeof(kTPThemes) / sizeof(kTPThemes[0]); }
+ (UIColor *)themeColorAtIndex:(NSInteger)i { return TPHex(kTPThemes[MAX(0, MIN(i, [self themeCount] - 1))].main); }
+ (NSString *)themeNameAtIndex:(NSInteger)i { return @(kTPThemes[MAX(0, MIN(i, [self themeCount] - 1))].name); }
+ (UIColor *)accent { return TPHex(TPCurrentTheme()->main); }
+ (UIColor *)accentIcon {
    const TPTheme *t = TPCurrentTheme();
    UIColor *dark = TPHex(t->iconDark), *light = TPHex(t->iconLight);
    return [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *tc) {
        return tc.userInterfaceStyle == UIUserInterfaceStyleDark ? dark : light;
    }];
}

+ (void)hapticLight {
    UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [g impactOccurred];
}
+ (void)hapticSuccess {
    UINotificationFeedbackGenerator *g = [UINotificationFeedbackGenerator new];
    [g notificationOccurred:UINotificationFeedbackTypeSuccess];
}
+ (void)hapticError {
    UINotificationFeedbackGenerator *g = [UINotificationFeedbackGenerator new];
    [g notificationOccurred:UINotificationFeedbackTypeError];
}

+ (UIButton *)circleButtonWithSymbol:(NSString *)symbol
                            diameter:(CGFloat)d
                             onTap:(void (^)(void))tap
                         menuItems:(NSArray<TPMenuItem *> *)menuItems {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(0, 0, d, d);
    b.layer.cornerRadius = d / 2;
    b.layer.borderWidth = 0.5;
    b.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.30].CGColor;
    b.layer.shadowColor = UIColor.blackColor.CGColor;
    b.layer.shadowOpacity = 0.18;
    b.layer.shadowRadius = 8;
    b.layer.shadowOffset = CGSizeMake(0, 2);

    // F 風格：超薄霧面 + 一層淡白，圖片亮或暗都看得清楚
    UIVisualEffectView *blur = [[UIVisualEffectView alloc]
        initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark]];
    blur.frame = b.bounds;
    blur.userInteractionEnabled = NO;
    blur.layer.cornerRadius = d / 2;
    blur.clipsToBounds = YES;
    UIView *frost = [[UIView alloc] initWithFrame:blur.bounds];
    frost.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
    frost.userInteractionEnabled = NO;
    [blur.contentView addSubview:frost];
    [b insertSubview:blur atIndex:0];

    // 圖示用獨立的 UIImageView 疊在毛玻璃「上面」；不用 UIButton 內建的 imageView，
    // 因為它可能被後加入的毛玻璃蓋住，結果只剩一個圓圈。
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:d * 0.40 weight:UIImageSymbolWeightSemibold];
    UIImage *img = [UIImage systemImageNamed:symbol withConfiguration:cfg];
    if (!img) img = [UIImage systemImageNamed:@"arrow.down" withConfiguration:cfg];
    UIImageView *icon = [[UIImageView alloc] initWithFrame:b.bounds];
    icon.contentMode = UIViewContentModeCenter;
    icon.userInteractionEnabled = NO;
    if (img) {
        icon.image = [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        icon.tintColor = UIColor.whiteColor;
    } else {
        UILabel *l = [[UILabel alloc] initWithFrame:b.bounds];     // 最後防線：純文字箭頭
        l.text = @"↓";
        l.textColor = UIColor.whiteColor;
        l.font = [UIFont systemFontOfSize:d * 0.5 weight:UIFontWeightBold];
        l.textAlignment = NSTextAlignmentCenter;
        [icon addSubview:l];
    }
    [b addSubview:icon];
    b.accessibilityLabel = TPL(@"Download");

    __weak UIButton *wb = b;
    [b addAction:[UIAction actionWithHandler:^(UIAction *a) {
        [UIView animateWithDuration:0.12 animations:^{ wb.transform = CGAffineTransformMakeScale(0.88, 0.88); }];
    }] forControlEvents:UIControlEventTouchDown];
    [b addAction:[UIAction actionWithHandler:^(UIAction *a) {
        [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.55 initialSpringVelocity:6
                            options:0 animations:^{ wb.transform = CGAffineTransformIdentity; } completion:nil];
    }] forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    if (tap) {
        [b addAction:[UIAction actionWithHandler:^(UIAction *a) { [TPUI hapticLight]; tap(); }]
         forControlEvents:UIControlEventTouchUpInside];
    }
    if (menuItems.count) {
        // 長按＝自己跳出底部選單（點一下仍是直接下載）。
        // 不用 UIButton.menu：系統選單動畫會把按鈕內容藏起來，結束後常只剩外框。
        TPLongPressMenuGesture *g = [[TPLongPressMenuGesture alloc] initWithTarget:self action:@selector(tp_longPressed:)];
        g.minimumPressDuration = 0.45;
        g.items = menuItems;
        [b addGestureRecognizer:g];
    }
    return b;
}

+ (void)tp_longPressed:(TPLongPressMenuGesture *)g {
    if (g.state != UIGestureRecognizerStateBegan) return;
    UIView *src = g.view;
    src.transform = CGAffineTransformIdentity;          // 確保按鈕回到原狀
    [TPUI hapticLight];

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    for (TPMenuItem *item in g.items) {
        void (^h)(void) = item.handler;
        UIAlertAction *a = [UIAlertAction actionWithTitle:item.title style:UIAlertActionStyleDefault
                                                  handler:^(UIAlertAction *x) { if (h) h(); }];
        UIImage *img = item.symbol ? [UIImage systemImageNamed:item.symbol] : nil;
        if (img) { @try { [a setValue:img forKey:@"image"]; } @catch (__unused id e) {} }
        [sheet addAction:a];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:TPL(@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = src;
    sheet.popoverPresentationController.sourceRect = src.bounds;
    [TPTopViewController() presentViewController:sheet animated:YES completion:nil];
}
@end
