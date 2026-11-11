#import "TPHUD.h"
#import "TPUI.h"
#import "TPLocalization.h"

static const CGFloat kCardW = 248;
static const CGFloat kRing  = 64;

@implementation TPHUD {
    UIView *_overlay;
    UIVisualEffectView *_card;
    CAShapeLayer *_track;
    CAShapeLayer *_ring;
    UIImageView *_icon;
    UILabel *_titleLabel;
    UILabel *_subLabel;
    UIButton *_cancelButton;
    void (^_cancel)(void);
    BOOL _finished;
}

#pragma mark - 建立

+ (instancetype)showWithTitle:(NSString *)title cancel:(void (^)(void))cancel {
    TPHUD *h = [TPHUD new];
    [h buildWithTitle:title cancel:cancel];
    return h;
}

- (void)buildWithTitle:(NSString *)title cancel:(void (^)(void))cancel {
    UIWindow *win = TPKeyWindow();
    if (!win) return;
    _cancel = [cancel copy];

    _overlay = [[UIView alloc] initWithFrame:win.bounds];
    _overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _overlay.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    _overlay.alpha = 0;

    CGFloat cardH = cancel ? 206 : 170;
    _card = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
    _card.frame = CGRectMake(0, 0, kCardW, cardH);
    _card.center = CGPointMake(CGRectGetMidX(win.bounds), CGRectGetMidY(win.bounds));
    _card.layer.cornerRadius = 24;
    _card.layer.cornerCurve = kCACornerCurveContinuous;
    _card.clipsToBounds = YES;
    _card.layer.borderWidth = 0.5;
    _card.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.14].CGColor;
    _card.autoresizingMask = UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin |
                             UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin;
    [_overlay addSubview:_card];
    UIView *content = _card.contentView;

    // 進度環
    CGPoint c = CGPointMake(kCardW / 2, 22 + kRing / 2);
    UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:c radius:(kRing - 6) / 2
                                                    startAngle:-M_PI_2 endAngle:M_PI * 1.5 clockwise:YES];
    _track = [CAShapeLayer layer];
    _track.path = path.CGPath;
    _track.fillColor = UIColor.clearColor.CGColor;
    _track.strokeColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
    _track.lineWidth = 4;
    [content.layer addSublayer:_track];

    _ring = [CAShapeLayer layer];
    _ring.path = path.CGPath;
    _ring.fillColor = UIColor.clearColor.CGColor;
    _ring.strokeColor = UIColor.whiteColor.CGColor;
    _ring.lineWidth = 4;
    _ring.lineCap = kCALineCapRound;
    _ring.strokeEnd = 0.02;
    [content.layer addSublayer:_ring];

    // 中央圖示
    _icon = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 28, 28)];
    _icon.center = c;
    _icon.contentMode = UIViewContentModeScaleAspectFit;
    _icon.tintColor = UIColor.whiteColor;
    _icon.image = [UIImage systemImageNamed:@"arrow.down"
                          withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold]];
    [content addSubview:_icon];

    // 標題／副標題
    _titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 100, kCardW - 32, 24)];
    _titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    _titleLabel.textColor = UIColor.whiteColor;
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.adjustsFontSizeToFitWidth = YES;
    _titleLabel.minimumScaleFactor = 0.75;
    _titleLabel.text = title;
    [content addSubview:_titleLabel];

    _subLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 126, kCardW - 32, 20)];
    _subLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightRegular];
    _subLabel.textColor = [UIColor colorWithWhite:1 alpha:0.6];
    _subLabel.textAlignment = NSTextAlignmentCenter;
    _subLabel.text = @"0%";
    [content addSubview:_subLabel];

    // 取消按鈕
    if (cancel) {
        UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, 160, kCardW, 0.5)];
        line.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12];
        [content addSubview:line];

        _cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
        _cancelButton.frame = CGRectMake(0, 160.5, kCardW, 45);
        _cancelButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        [_cancelButton setTitle:TPL(@"Cancel") forState:UIControlStateNormal];
        [_cancelButton setTitleColor:[UIColor colorWithWhite:1 alpha:0.85] forState:UIControlStateNormal];
        [_cancelButton addTarget:self action:@selector(cancelTapped) forControlEvents:UIControlEventTouchUpInside];
        [content addSubview:_cancelButton];
    }

    [win addSubview:_overlay];
    _card.transform = CGAffineTransformMakeScale(0.88, 0.88);
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.78 initialSpringVelocity:0.6
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{ self->_overlay.alpha = 1; self->_card.transform = CGAffineTransformIdentity; }
                     completion:nil];
}

#pragma mark - 更新

- (void)setTitle:(NSString *)title {
    dispatch_async(dispatch_get_main_queue(), ^{ self->_titleLabel.text = title; });
}

- (void)setProgress:(CGFloat)progress subtitle:(NSString *)subtitle {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_finished) return;
        CGFloat p = MAX(0.02, MIN(1.0, progress));
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        self->_ring.strokeEnd = p;
        [CATransaction commit];
        self->_subLabel.text = subtitle ?: [NSString stringWithFormat:@"%.0f%%", p * 100];
    });
}

- (void)cancelTapped {
    if (_finished) return;
    void (^cb)(void) = _cancel;
    [self dismiss];
    if (cb) cb();
}

#pragma mark - 結束狀態

- (void)finishWithSymbol:(NSString *)symbol color:(UIColor *)color message:(NSString *)message hold:(NSTimeInterval)hold {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_finished || !self->_overlay) return;
        self->_finished = YES;

        self->_ring.strokeColor = color.CGColor;
        [CATransaction begin];
        [CATransaction setAnimationDuration:0.25];
        self->_ring.strokeEnd = 1.0;
        [CATransaction commit];

        self->_icon.tintColor = color;
        self->_icon.image = [UIImage systemImageNamed:symbol
                                    withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:28 weight:UIImageSymbolWeightBold]];
        self->_icon.transform = CGAffineTransformMakeScale(0.4, 0.4);
        [UIView animateWithDuration:0.45 delay:0 usingSpringWithDamping:0.5 initialSpringVelocity:8
                            options:0 animations:^{ self->_icon.transform = CGAffineTransformIdentity; } completion:nil];

        self->_titleLabel.text = message;
        self->_subLabel.text = @"";
        [self->_cancelButton removeFromSuperview];

        // 卡片收成較矮的樣式
        [UIView animateWithDuration:0.25 animations:^{
            CGPoint c = self->_card.center;
            self->_card.bounds = CGRectMake(0, 0, kCardW, 156);
            self->_card.center = c;
        }];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(hold * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self dismiss];
        });
    });
}

- (void)finishSuccess:(NSString *)message {
    [TPUI hapticSuccess];
    [self finishWithSymbol:@"checkmark" color:UIColor.systemGreenColor message:message hold:1.2];
}

- (void)finishFailure:(NSString *)message {
    [TPUI hapticError];
    [self finishWithSymbol:@"xmark" color:UIColor.systemRedColor message:message hold:1.8];
}

- (void)dismiss {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *ov = self->_overlay;
        if (!ov) return;
        self->_overlay = nil;
        [UIView animateWithDuration:0.22 animations:^{
            ov.alpha = 0;
            self->_card.transform = CGAffineTransformMakeScale(0.92, 0.92);
        } completion:^(BOOL f) { [ov removeFromSuperview]; }];
    });
}

#pragma mark - Toast

// 同時出現多則提示時往上疊，不互相蓋住；最新的在最下面
static NSMutableArray<UIView *> *sTPToasts;

static void TPLayoutToasts(UIWindow *win, BOOL animated) {
    CGFloat bottom = win.bounds.size.height - win.safeAreaInsets.bottom - 86;
    for (UIView *v in sTPToasts.reverseObjectEnumerator) {
        CGRect f = v.frame;
        f.origin.y = bottom - f.size.height;
        bottom = f.origin.y - 8;
        if (animated) [UIView animateWithDuration:0.25 animations:^{ v.frame = f; }];
        else v.frame = f;
    }
}

+ (void)toast:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *win = TPKeyWindow();
        if (!win || !text.length) return;
        if (!sTPToasts) sTPToasts = [NSMutableArray array];
        while (sTPToasts.count >= 4) { [sTPToasts.firstObject removeFromSuperview]; [sTPToasts removeObjectAtIndex:0]; }

        UIVisualEffectView *pill = [[UIVisualEffectView alloc]
            initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
        pill.layer.cornerRadius = 20;
        pill.layer.cornerCurve = kCACornerCurveContinuous;
        pill.clipsToBounds = YES;
        pill.layer.borderWidth = 0.5;
        pill.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.15].CGColor;

        UILabel *l = [UILabel new];
        l.text = text;
        l.textColor = UIColor.whiteColor;
        l.font = [UIFont systemFontOfSize:14.5 weight:UIFontWeightMedium];
        l.numberOfLines = 0;
        l.textAlignment = NSTextAlignmentCenter;

        CGFloat maxW = win.bounds.size.width - 72;
        CGSize s = [l sizeThatFits:CGSizeMake(maxW, CGFLOAT_MAX)];
        CGFloat w = MIN(s.width, maxW) + 36, h = s.height + 24;
        l.frame = CGRectMake(18, 12, w - 36, s.height);
        [pill.contentView addSubview:l];
        pill.frame = CGRectMake((win.bounds.size.width - w) / 2, 0, w, h);
        [sTPToasts addObject:pill];
        [win addSubview:pill];
        TPLayoutToasts(win, YES);                 // 舊的往上推，新的放最下面
        pill.alpha = 0;
        pill.transform = CGAffineTransformMakeTranslation(0, 14);

        // 多行的提示停久一點，讓人看得完
        NSTimeInterval stay = 2.0 + MAX(0, (NSInteger)[text componentsSeparatedByString:@"\n"].count - 1) * 1.5;
        [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:0
                         animations:^{ pill.alpha = 1; pill.transform = CGAffineTransformIdentity; } completion:^(BOOL f) {
            [UIView animateWithDuration:0.3 delay:stay options:0 animations:^{ pill.alpha = 0; }
                             completion:^(BOOL f2) {
                [pill removeFromSuperview];
                if ([sTPToasts containsObject:pill]) {
                    [sTPToasts removeObject:pill];
                    if (pill.window || win) TPLayoutToasts(win, YES);
                }
            }];
        }];
    });
}
#pragma mark - Banner

static UIView *sTPBanner;

+ (void)dismissBanner:(UIView *)v {
    if (!v || v != sTPBanner) return;
    sTPBanner = nil;
    [UIView animateWithDuration:0.25 animations:^{
        v.alpha = 0;
        v.transform = CGAffineTransformMakeTranslation(0, -20);
    } completion:^(BOOL f) { [v removeFromSuperview]; }];
}

+ (void)bannerWithText:(NSString *)text symbol:(NSString *)symbol action:(NSString *)actionTitle handler:(void (^)(void))handler {
    [self bannerWithText:text symbol:symbol action:actionTitle position:0 handler:handler];
}

+ (void)bannerWithText:(NSString *)text symbol:(NSString *)symbol action:(NSString *)actionTitle
              position:(NSInteger)position handler:(void (^)(void))handler {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *win = TPKeyWindow();
        if (!win) return;
        if (sTPBanner) { [sTPBanner removeFromSuperview]; sTPBanner = nil; }

        CGFloat w = MIN(win.bounds.size.width - 32, 420), h = 52;
        UIVisualEffectView *bar = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterialDark]];
        CGFloat y;
        if (position == 1)      y = (win.bounds.size.height - h) / 2;
        else if (position == 2) y = win.bounds.size.height - win.safeAreaInsets.bottom - h - 84;   // 分頁列上方
        else                    y = win.safeAreaInsets.top + 8;
        bar.frame = CGRectMake((win.bounds.size.width - w) / 2, y, w, h);
        bar.layer.cornerRadius = h / 2;
        bar.layer.cornerCurve = kCACornerCurveContinuous;
        bar.clipsToBounds = YES;
        bar.layer.borderWidth = 0.5;
        bar.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.15].CGColor;

        UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(16, (h - 22) / 2, 22, 22)];
        icon.image = [UIImage systemImageNamed:symbol ?: @"link"
                             withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold]];
        icon.contentMode = UIViewContentModeCenter;
        icon.tintColor = [UIColor colorWithWhite:1 alpha:0.85];
        [bar.contentView addSubview:icon];

        UILabel *action = [UILabel new];
        action.text = actionTitle;
        action.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        action.textColor = UIColor.whiteColor;
        action.textAlignment = NSTextAlignmentCenter;
        action.backgroundColor = [TPUI accent];
        action.layer.cornerRadius = 15;
        action.clipsToBounds = YES;
        CGFloat aw = MAX(64, [action sizeThatFits:CGSizeMake(200, 30)].width + 24);
        action.frame = CGRectMake(w - aw - 11, (h - 30) / 2, aw, 30);
        [bar.contentView addSubview:action];

        UILabel *label = [UILabel new];
        label.text = text;
        label.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        label.textColor = UIColor.whiteColor;
        label.frame = CGRectMake(46, 0, CGRectGetMinX(action.frame) - 54, h);
        [bar.contentView addSubview:label];

        __weak UIView *weakBar = bar;
        void (^tap)(void) = [handler copy];
        UIButton *hit = [UIButton buttonWithType:UIButtonTypeCustom];
        hit.frame = bar.bounds;
        [hit addAction:[UIAction actionWithHandler:^(UIAction *a) {
            [TPHUD dismissBanner:weakBar];
            if (tap) tap();
        }] forControlEvents:UIControlEventTouchUpInside];
        [bar.contentView addSubview:hit];

        UISwipeGestureRecognizer *swipe = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(tp_bannerSwiped:)];
        swipe.direction = (position == 2) ? UISwipeGestureRecognizerDirectionDown
                                          : (UISwipeGestureRecognizerDirectionUp | UISwipeGestureRecognizerDirectionDown);
        [bar addGestureRecognizer:swipe];

        sTPBanner = bar;
        [win addSubview:bar];
        bar.alpha = 0;
        bar.transform = position == 1 ? CGAffineTransformMakeScale(0.9, 0.9)
                                      : CGAffineTransformMakeTranslation(0, position == 2 ? 24 : -24);
        [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:0
                         animations:^{ bar.alpha = 1; bar.transform = CGAffineTransformIdentity; } completion:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [TPHUD dismissBanner:weakBar];
        });
    });
}

+ (void)tp_bannerSwiped:(UISwipeGestureRecognizer *)g {
    [TPHUD dismissBanner:g.view];
}
@end

