#import "TPDownloader.h"
#import "TPVersion.h"
#import "TPPrefs.h"
#import "TPLocalization.h"
#import <Photos/Photos.h>
#import <objc/runtime.h>
#import "TPUI.h"
#import "TPHUD.h"

/// 依序下載多個項目（影片／圖片），顯示進度視窗並存入「照片」。
@interface TPDownloadJob : NSObject <NSURLSessionDownloadDelegate>
- (instancetype)initWithItems:(NSArray<NSDictionary *> *)items;
- (void)start;
@end

static NSString *sPendingReport;          // 下一個下載工作結束時要顯示的除錯報告

@implementation TPDownloader

#pragma mark - Helpers

+ (UIViewController *)topViewController { return TPTopViewController(); }

+ (void)toast:(NSString *)text { [TPHUD toast:text]; }

/// 安全取值：避免對 Swift/ObjC 混合物件用 KVC 時因 key 不存在而崩潰。
static id TPSafeValue(id obj, NSString *key) {
    if (!obj) return nil;
    SEL sel = NSSelectorFromString(key);
    if ([obj respondsToSelector:sel]) {
        @try { return [obj valueForKey:key]; } @catch (__unused id e) {}
    }
    return nil;
}

/// 讀數字：支援 NSNumber，以及 Meta 的 FBBoxedInteger（值放在 value / integerValue 等不同方法裡）
static NSInteger TPInt(id v) {
    if (!v) return 0;
    if ([v respondsToSelector:@selector(integerValue)]) return [v integerValue];
    for (NSString *key in @[@"value", @"longLongValue", @"intValue"]) {
        if (![v respondsToSelector:NSSelectorFromString(key)]) continue;
        @try {
            id n = [v valueForKey:key];
            if ([n respondsToSelector:@selector(integerValue)]) return [n integerValue];
        } @catch (__unused id e) {}
    }
    return 0;
}

/// 替候選網址打分數：-1 = 排除（純音訊）。數字越大解析度越高。
static NSInteger TPScoreURL(NSURL *u) {
    NSString *abs = u.absoluteString;
    NSString *tag = @"";
    NSURLComponents *c = [NSURLComponents componentsWithURL:u resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *q in c.queryItems) {
        if ([q.name isEqualToString:@"efg"] && q.value.length) {
            NSString *b64 = [[q.value stringByReplacingOccurrencesOfString:@"-" withString:@"+"]
                             stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
            while (b64.length % 4) b64 = [b64 stringByAppendingString:@"="];
            NSData *d = [[NSData alloc] initWithBase64EncodedString:b64 options:0];
            NSString *js = d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : nil;
            if (js) tag = js;
        }
    }
    NSString *lower = tag.lowercaseString;
    if ([lower containsString:@"audio"] || [lower containsString:@"heaac"]) return -1;

    NSInteger score = 1;
    if ([abs.lowercaseString containsString:@".mp4"]) score += 50;
    if ([lower containsString:@"progressive"]) score += 100000;      // 含音訊的單一 mp4
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"\\.(\\d{3,4})\\." options:0 error:nil];
    NSTextCheckingResult *r = [re firstMatchInString:tag options:0 range:NSMakeRange(0, tag.length)];
    if (r) score += [[tag substringWithRange:[r rangeAtIndex:1]] integerValue];
    return score;
}

#pragma mark - URL selection

+ (NSURL *)bestURLFromObject:(id)obj {
    if (!obj) return nil;

    // 相容：傳進來的可能是 IGVideo，也可能是包了 video 的 IGMedia
    NSArray *versions = TPSafeValue(obj, @"videoVersions");
    if (![versions isKindOfClass:[NSArray class]] || versions.count == 0) {
        id inner = TPSafeValue(obj, @"video");
        versions = TPSafeValue(inner, @"videoVersions");
    }

    NSURL *best = nil;                   // 一律挑最高畫質
    NSInteger bestScore = -1;

    for (id ver in versions) {
        NSString *s = TPSafeValue(ver, @"urlString");
        if (![s isKindOfClass:[NSString class]] || s.length == 0) {
            // 部分版本只提供 URL 物件
            id u = TPSafeValue(ver, @"url");
            if ([u isKindOfClass:[NSURL class]]) s = [(NSURL *)u absoluteString];
        }
        if (!s.length) continue;
        NSInteger w = TPInt(TPSafeValue(ver, @"width"));
        NSInteger h = TPInt(TPSafeValue(ver, @"height"));
        NSInteger score = w * h;
        if (score == 0) score = TPInt(TPSafeValue(ver, @"bandwidth"));
        if (score > bestScore) {
            NSURL *u = [NSURL URLWithString:s];
            if (u) { best = u; bestScore = score; }
        }
    }

    // 備援：IGVideoURLProvider 的 allVideoURLs / videoURLForCurrentNetworkConditions
    if (!best) {
        id all = TPSafeValue(obj, @"allVideoURLs");
        NSInteger bs = -1;
        for (id u in all) {
            if (![u isKindOfClass:[NSURL class]]) continue;
            NSInteger sc = TPScoreURL(u);
            if (sc < 0) continue;
            if (!best || sc > bs) { best = u; bs = sc; }
        }
    }
    if (!best) {
        id u = TPSafeValue(obj, @"videoURLForCurrentNetworkConditions");
        if ([u isKindOfClass:[NSURL class]]) best = u;
    }
    return best;
}


#pragma mark - From IGVideoView

/// 以 runtime 讀取 Swift 物件的實例變數（名稱不含底線前綴）。
static id TPIvarObject(id obj, const char *name) {
    for (Class c = [obj class]; c; c = class_getSuperclass(c)) {
        Ivar iv = class_getInstanceVariable(c, name);
        if (iv) return object_getIvar(obj, iv);
    }
    return nil;
}

static id TPResolvePlayer(UIView *view, id hint) {
    if (hint) return hint;                           // 由播放器回呼記下的物件（最可靠）
    return TPIvarObject(view, "videoPlayer");        // 備援：直接讀 Swift 實例變數
}

/// 外層 IGVideoPlayer(Swift 包裝) → .videoPlayer / _videoPlayer (IGFNFVideoPlayer) → .video (IGVideoURLProvider)
static id TPInnerPlayer(id player) {
    id inner = TPSafeValue(player, @"videoPlayer");
    if (!inner) inner = TPIvarObject(player, "_videoPlayer");
    return inner;
}

static id TPFindProvider(id player) {
    if (!player) return nil;
    id p = TPSafeValue(player, @"video");
    if (p) return p;
    id inner = TPInnerPlayer(player);
    p = TPSafeValue(inner, @"video");
    if (p) return p;
    // 備援：換影片時暫存的 provider
    return TPIvarObject(player, "pendingVideoToReload");
}

+ (NSURL *)bestURLFromVideoView:(UIView *)view player:(id)hint {
    if (!view) return nil;
    id player = TPResolvePlayer(view, hint);
    NSURL *u = [self bestURLFromObject:TPFindProvider(player)];
    if (!u) u = [self bestURLFromObject:TPInnerPlayer(player)];
    if (!u) u = [self bestURLFromObject:player];
    return u;
}

static NSString *TPShort(id v) {
    NSString *d = v ? [v description] : @"nil";
    return d.length > 380 ? [[d substringToIndex:380] stringByAppendingString:@"…"] : d;
}

+ (NSString *)debugReportForVideoView:(UIView *)view player:(id)hint {
    id ivarPlayer = TPIvarObject(view, "videoPlayer");
    id player = TPResolvePlayer(view, hint);
    id inner = TPInnerPlayer(player);
    id provider = TPFindProvider(player);
    NSMutableString *r = [NSMutableString string];
    [r appendFormat:@"ThreadsPulse %@\n", TP_VERSION];
    [r appendFormat:@"view: %@\n", NSStringFromClass([view class])];
    [r appendFormat:@"player (callback): %@\n", hint ? NSStringFromClass([hint class]) : @"nil"];
    [r appendFormat:@"player (ivar): %@\n", ivarPlayer ? NSStringFromClass([ivarPlayer class]) : @"nil"];
    [r appendFormat:@"inner player: %@\n", inner ? NSStringFromClass([inner class]) : @"nil"];
    [r appendFormat:@"provider: %@\n", provider ? NSStringFromClass([provider class]) : @"nil"];
    [r appendFormat:@"allVideoURLs: %@\n", TPShort(TPSafeValue(provider, @"allVideoURLs"))];
    [r appendFormat:@"URL for current network: %@\n", TPShort(TPSafeValue(provider, @"videoURLForCurrentNetworkConditions"))];
    id vv = TPSafeValue(provider, @"videoVersions");
    [r appendFormat:@"videoVersions: %@\n", vv ? TPShort(vv) : @"none"];
    NSData *dash = TPSafeValue(provider, @"dashManifestData");
    if (![dash isKindOfClass:[NSData class]]) dash = TPSafeValue(inner, @"dashManifestData");
    if (![dash isKindOfClass:[NSData class]]) dash = TPSafeValue(player, @"currentMPD");
    if ([dash isKindOfClass:[NSData class]]) {
        NSString *x = [[NSString alloc] initWithData:dash encoding:NSUTF8StringEncoding];
        [r appendFormat:@"DASH manifest: %lu bytes\n%@\n", (unsigned long)dash.length, TPShort(x)];
    } else {
        [r appendString:@"DASH manifest: none\n"];
    }
    return r;
}

+ (void)showReport:(NSString *)text {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIViewController *top = [self topViewController];
        UIAlertController *a = [UIAlertController alertControllerWithTitle:TPL(@"Diagnostics")
                                                                   message:text
                                                            preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:TPL(@"Copy") style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
            UIPasteboard.generalPasteboard.string = text;
        }]];
        [a addAction:[UIAlertAction actionWithTitle:TPL(@"Close") style:UIAlertActionStyleCancel handler:nil]];
        [top presentViewController:a animated:YES completion:nil];
    });
}


#pragma mark - 從資料物件中找出媒體網址

/// 遞迴走訪物件的實例變數（只看 ObjC 物件型別），蒐集所有 http(s) 網址。
/// 用於「還沒播放／還沒載入」的項目：GraphQL 資料物件裡通常已經帶有完整的媒體網址。
static void TPHarvest(id obj, int depth, NSMutableSet<NSValue *> *visited, NSMutableArray<NSURL *> *out, int *budget) {
    if (!obj || depth > 8 || *budget <= 0) return;
    (*budget)--;

    if ([obj isKindOfClass:[NSURL class]]) {
        NSString *sch = [(NSURL *)obj scheme].lowercaseString;
        if ([sch isEqualToString:@"http"] || [sch isEqualToString:@"https"]) [out addObject:obj];
        return;
    }
    if ([obj isKindOfClass:[NSString class]]) {
        NSString *str = obj;
        if (str.length > 12 && str.length < 3000 && ([str hasPrefix:@"https://"] || [str hasPrefix:@"http://"])) {
            NSURL *u = [NSURL URLWithString:str];
            if (u) [out addObject:u];
        }
        return;
    }
    if ([obj isKindOfClass:[NSNumber class]] || [obj isKindOfClass:[NSDate class]] || [obj isKindOfClass:[NSData class]]) return;
    if ([obj isKindOfClass:[UIResponder class]] || [obj isKindOfClass:[CALayer class]] || [obj isKindOfClass:[UIImage class]]) return;

    if ([obj isKindOfClass:[NSDictionary class]]) {
        for (id v in [(NSDictionary *)obj allValues]) TPHarvest(v, depth + 1, visited, out, budget);
        return;
    }
    if ([obj isKindOfClass:[NSArray class]] || [obj isKindOfClass:[NSSet class]] || [obj isKindOfClass:[NSOrderedSet class]]) {
        for (id v in obj) TPHarvest(v, depth + 1, visited, out, budget);
        return;
    }

    NSValue *key = [NSValue valueWithPointer:(__bridge const void *)obj];
    if ([visited containsObject:key]) return;
    [visited addObject:key];

    for (Class c = object_getClass(obj); c && c != [NSObject class]; c = class_getSuperclass(c)) {
        unsigned int n = 0;
        Ivar *ivars = class_copyIvarList(c, &n);
        for (unsigned int i = 0; i < n; i++) {
            const char *enc = ivar_getTypeEncoding(ivars[i]);
            if (!enc || enc[0] != '@' || enc[1] == '?') continue;      // 只處理物件型別，略過 block 與數值
            id v = object_getIvar(obj, ivars[i]);
            TPHarvest(v, depth + 1, visited, out, budget);
        }
        free(ivars);
    }
}

static NSArray<NSURL *> *TPHarvestURLs(id obj) {
    NSMutableArray<NSURL *> *out = [NSMutableArray array];
    NSMutableSet<NSValue *> *visited = [NSMutableSet set];
    int budget = 4000;                                                   // 節點上限，避免走太深
    TPHarvest(obj, 0, visited, out, &budget);
    return out;
}

static NSInteger TPImageScore(NSURL *u) {
    NSString *s = u.absoluteString;
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"(\\d{3,4})x(\\d{3,4})" options:0 error:nil];
    NSTextCheckingResult *m = [re firstMatchInString:s options:0 range:NSMakeRange(0, s.length)];
    if (!m) return 1;
    return [[s substringWithRange:[m rangeAtIndex:1]] integerValue] * [[s substringWithRange:[m rangeAtIndex:2]] integerValue];
}

#pragma mark - 對外 API


+ (NSURL *)bestVideoURLHarvestedFromObject:(id)obj {
    NSURL *best = nil;                   // 一律挑最高畫質
    NSInteger bs = -1;
    for (NSURL *u in TPHarvestURLs(obj)) {
        if (![u.path.lowercaseString containsString:@".mp4"]) continue;
        NSInteger sc = TPScoreURL(u);
        if (sc < 0) continue;
        if (!best || sc > bs) { best = u; bs = sc; }
    }
    return best;
}

static NSURL *TPBestImageURLIn(id obj) {
    NSURL *best = nil;
    NSInteger bs = -1;
    for (NSURL *u in TPHarvestURLs(obj)) {
        NSString *path = u.path.lowercaseString;
        BOOL isImage = NO;
        for (NSString *ext in @[@".jpg", @".jpeg", @".webp", @".heic", @".png"]) if ([path containsString:ext]) { isImage = YES; break; }
        if (!isImage) continue;
        if ([path containsString:@"-19/"]) continue;                  // 略過大頭貼（Meta CDN 上大頭貼的路徑特徵）
        NSInteger sc = TPImageScore(u);
        if (sc > bs) { best = u; bs = sc; }
    }
    return best;
}

+ (NSURL *)bestImageURLHarvestedFromObject:(id)obj { return TPBestImageURLIn(obj); }

+ (NSURL *)bestVideoURLNearView:(UIView *)view {
    int level = 0;
    for (UIView *v = view; v && level < 8; v = v.superview, level++) {
        NSMutableArray *models = [NSMutableArray array];
        for (Class c = object_getClass(v); c && c != [UIView class]; c = class_getSuperclass(c)) {
            unsigned int n = 0;
            Ivar *ivars = class_copyIvarList(c, &n);
            for (unsigned int i = 0; i < n; i++) {
                const char *enc = ivar_getTypeEncoding(ivars[i]);
                if (!enc || enc[0] != '@' || enc[1] == '?') continue;      // 只看物件型別的欄位
                id o = object_getIvar(v, ivars[i]);
                if (o && ![o isKindOfClass:[UIResponder class]] && ![o isKindOfClass:[CALayer class]]) [models addObject:o];
            }
            free(ivars);
        }
        NSURL *u = models.count ? [self bestVideoURLHarvestedFromObject:models] : nil;
        if (u) return u;
    }
    return nil;
}


+ (id)safeValue:(id)obj key:(NSString *)key { return TPSafeValue(obj, key); }

+ (double)imageAreaFromURL:(NSURL *)url { return (double)TPImageScore(url); }

+ (void)setPendingReport:(NSString *)report { sPendingReport = [report copy]; }

+ (void)appendPendingReport:(NSString *)report {
    if (![TPPrefs boolForKey:TPKeyDebugToast] || !report.length) return;
    sPendingReport = sPendingReport ? [sPendingReport stringByAppendingString:report] : [report copy];
}

+ (id)ivarValue:(id)obj name:(NSString *)name {
    if (!obj || !name.length) return nil;
    for (Class c = [obj class]; c; c = class_getSuperclass(c)) {
        Ivar iv = class_getInstanceVariable(c, name.UTF8String);
        if (iv) return object_getIvar(obj, iv);
    }
    return nil;
}

+ (void)downloadItems:(NSArray<NSDictionary *> *)items {
    if (!items.count) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        TPDownloadJob *job = [[TPDownloadJob alloc] initWithItems:items];
        [job start];
    });
}

+ (void)downloadVideoURL:(NSURL *)url {
    if (!url) return;
    [self downloadItems:@[@{ @"urls": @[url], @"video": @YES }]];
}

@end

#pragma mark - 下載工作

static NSMutableSet *sJobs;   // 讓工作在下載期間不被釋放

/// 讀檔頭判斷圖片格式。只回傳照片 App 一定吃得下的格式（jpg／png／heic）；
/// 其他像 AVIF、WebP 回傳 nil，改走「解碼成 UIImage 再存」。
static NSString *TPImageExtension(NSURL *file) {
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingFromURL:file error:nil];
    NSData *d = [fh readDataOfLength:16];
    [fh closeFile];
    if (d.length < 12) return nil;
    const uint8_t *b = d.bytes;
    if (b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return @"jpg";
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return @"png";
    if (b[4] == 'f' && b[5] == 't' && b[6] == 'y' && b[7] == 'p') {
        NSString *brand = [[NSString alloc] initWithBytes:b + 8 length:4 encoding:NSASCIIStringEncoding];
        if ([@[@"heic", @"heix", @"hevc", @"heim", @"heis", @"mif1", @"msf1"] containsObject:brand]) return @"heic";
    }
    return nil;                       // avif、webp 等
}

/// 檔頭簡述（給診斷用）：例如 "ftyp/avif"、"RIFF/WEBP"、"<htm"
static NSString *TPMagicString(NSURL *file) {
    NSFileHandle *fh = [NSFileHandle fileHandleForReadingFromURL:file error:nil];
    NSData *d = [fh readDataOfLength:16];
    [fh closeFile];
    if (d.length < 12) return [NSString stringWithFormat:@"%lu bytes", (unsigned long)d.length];
    const uint8_t *b = d.bytes;
    if (b[4] == 'f' && b[5] == 't' && b[6] == 'y' && b[7] == 'p')
        return [@"ftyp/" stringByAppendingString:[[NSString alloc] initWithBytes:b + 8 length:4 encoding:NSASCIIStringEncoding] ?: @"?"];
    if (b[0] == 'R' && b[1] == 'I' && b[2] == 'F' && b[3] == 'F')
        return [@"RIFF/" stringByAppendingString:[[NSString alloc] initWithBytes:b + 8 length:4 encoding:NSASCIIStringEncoding] ?: @"?"];
    NSMutableString *hex = [NSMutableString string];
    for (int i = 0; i < 4; i++) [hex appendFormat:@"%02X", b[i]];
    return hex;
}

/// 把任何 UIImage（例如 WebP 解碼出來的）重新繪製成標準 8 位元 sRGB，再轉成 JPEG。
/// 照片 App 對某些解碼後的像素格式會回 PHPhotosErrorDomain 3302（資源無效），轉成 JPEG 就一定收。
static NSData *TPJPEGData(UIImage *img) {
    if (!img) return nil;
    CGSize px = CGSizeMake(img.size.width * img.scale, img.size.height * img.scale);
    if (px.width < 1 || px.height < 1) return nil;
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    fmt.scale = 1;
    fmt.opaque = YES;
    fmt.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
    UIImage *flat = [[[UIGraphicsImageRenderer alloc] initWithSize:px format:fmt] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [UIColor.whiteColor setFill];                      // 透明背景補白，避免變黑
        UIRectFill(CGRectMake(0, 0, px.width, px.height));
        [img drawInRect:CGRectMake(0, 0, px.width, px.height)];
    }];
    return UIImageJPEGRepresentation(flat, 0.95);
}

@implementation TPDownloadJob {
    NSArray<NSDictionary *> *_items;
    NSInteger _index, _urlIndex, _saved, _failed;
    NSURLSession *_session;
    NSURLSessionDownloadTask *_task;
    TPHUD *_hud;
    BOOL _cancelled, _allowPhotos;
    NSURL *_pendingFile;
    NSMutableArray<NSURL *> *_leftovers;   // 沒有相簿權限時，留給分享面板的檔案
    NSMutableArray<NSString *> *_log;      // 失敗原因（除錯提示開啟時顯示）
    NSString *_extraReport;                // 附加報告（例如照片可用尺寸）
    NSMutableArray<NSString *> *_savedSizes;
}

- (instancetype)initWithItems:(NSArray<NSDictionary *> *)items {
    if ((self = [super init])) {
        _items = items;
        _leftovers = [NSMutableArray array];
        _log = [NSMutableArray array];
        _savedSizes = [NSMutableArray array];
        _extraReport = sPendingReport;
        sPendingReport = nil;
    }
    return self;
}

- (void)start {
    if (!sJobs) sJobs = [NSMutableSet set];
    [sJobs addObject:self];

    PHAuthorizationStatus st = [PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelAddOnly];
    if (st == PHAuthorizationStatusNotDetermined) {
        [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus s2) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self->_allowPhotos = (s2 == PHAuthorizationStatusAuthorized || s2 == PHAuthorizationStatusLimited);
                [self begin];
            });
        }];
    } else {
        _allowPhotos = (st == PHAuthorizationStatusAuthorized || st == PHAuthorizationStatusLimited);
        [self begin];
    }
}

- (void)begin {
    __weak typeof(self) weak = self;
    _hud = [TPHUD showWithTitle:[self titleForCurrent] cancel:^{ [weak cancel]; }];
    NSURLSessionConfiguration *cfg = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    _session = [NSURLSession sessionWithConfiguration:cfg delegate:self delegateQueue:NSOperationQueue.mainQueue];
    [self tryCurrent];
}

- (void)cancel {
    _cancelled = YES;
    [_session invalidateAndCancel];
    for (NSURL *f in _leftovers) [NSFileManager.defaultManager removeItemAtURL:f error:nil];
    [sJobs removeObject:self];
}

- (NSString *)titleForCurrent {
    if (_items.count <= 1) return TPL(@"Downloading…");
    return [NSString stringWithFormat:TPL(@"Downloading %ld of %ld"), (long)MIN(_index + 1, (NSInteger)_items.count), (long)_items.count];
}

#pragma mark - 流程

- (void)nextItem {
    _index++;
    _urlIndex = 0;
    if (_index >= (NSInteger)_items.count) { [self finish]; return; }
    [_hud setTitle:[self titleForCurrent]];
    [self tryCurrent];
}

- (void)tryCurrent {
    if (_cancelled) return;
    NSDictionary *item = _items[_index];
    NSArray<NSURL *> *urls = item[@"urls"];
    if (_urlIndex >= (NSInteger)urls.count) {
        // 所有網址都失敗：圖片可退而求其次，直接存畫面上已載入的那張
        UIImage *fallback = item[@"image"];
        if ([fallback isKindOfClass:[UIImage class]] && _allowPhotos) {
            [self saveImage:fallback];
        } else {
            if (!urls.count) [self note:@"no URL"];
            _failed++;
            [self nextItem];
        }
        return;
    }
    _pendingFile = nil;
    _task = [_session downloadTaskWithURL:urls[_urlIndex]];
    [_task resume];
}

- (void)finish {
    [_session finishTasksAndInvalidate];
    [sJobs removeObject:self];

    if (_leftovers.count) {
        // 沒有「照片」權限：讓使用者用分享面板決定存到哪裡
        [_hud dismiss];
        UIViewController *top = TPTopViewController();
        UIActivityViewController *av = [[UIActivityViewController alloc] initWithActivityItems:_leftovers applicationActivities:nil];
        av.popoverPresentationController.sourceView = top.view;
        av.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(top.view.bounds), CGRectGetMidY(top.view.bounds), 1, 1);
        [top presentViewController:av animated:YES completion:nil];
        [TPHUD toast:TPL(@"Photos access denied — choose where to save")];
        return;
    }

    if (_extraReport && [TPPrefs boolForKey:TPKeyDebugToast]) {
        NSMutableString *r = [NSMutableString stringWithFormat:@"ThreadsPulse %@\n%@", TP_VERSION, _extraReport];
        if (_savedSizes.count) [r appendFormat:@"\n[downloaded]\n%@\n", [_savedSizes componentsJoinedByString:@"\n"]];
        if (_log.count) [r appendFormat:@"\n[errors]\n%@", [_log componentsJoinedByString:@"\n"]];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [TPDownloader showReport:r];
        });
    } else if (_failed > 0 && _log.count && [TPPrefs boolForKey:TPKeyDebugToast]) {
        NSString *report = [NSString stringWithFormat:@"ThreadsPulse %@\n%@", TP_VERSION,
                            [_log componentsJoinedByString:@"\n"]];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [TPDownloader showReport:report];
        });
    }
    if (_saved == 0) { [_hud finishFailure:TPL(@"Download failed, please try again later")]; return; }
    if (_failed > 0) {
        [_hud finishSuccess:[NSString stringWithFormat:TPL(@"Saved %ld, failed %ld"), (long)_saved, (long)_failed]];
    } else if (_saved == 1) {
        [_hud finishSuccess:TPL(@"Saved to Photos")];
    } else {
        [_hud finishSuccess:[NSString stringWithFormat:TPL(@"Saved %ld items to Photos"), (long)_saved]];
    }
}

#pragma mark - NSURLSession

- (void)URLSession:(NSURLSession *)s downloadTask:(NSURLSessionDownloadTask *)t didWriteData:(int64_t)w
 totalBytesWritten:(int64_t)tw totalBytesExpectedToWrite:(int64_t)te {
    if (t != _task || _cancelled) return;
    double mb = tw / 1048576.0;
    CGFloat frac = te > 0 ? (CGFloat)tw / (CGFloat)te : 0;
    CGFloat overall = ((CGFloat)_index + frac) / (CGFloat)_items.count;
    NSString *sub = te > 0 ? [NSString stringWithFormat:@"%.0f%%  ·  %.1f / %.1f MB", frac * 100, mb, te / 1048576.0]
                           : [NSString stringWithFormat:@"%.1f MB", mb];
    [_hud setProgress:overall subtitle:sub];
}

- (void)URLSession:(NSURLSession *)s downloadTask:(NSURLSessionDownloadTask *)t didFinishDownloadingToURL:(NSURL *)loc {
    if (t != _task) return;
    NSInteger code = [t.response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)t.response statusCode] : 200;
    if (code < 200 || code >= 300) return;     // 403 等錯誤頁面不算成功，交給 didComplete 換下一個網址
    NSURL *dst = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                                         [NSString stringWithFormat:@"tp_%@", NSUUID.UUID.UUIDString]]];
    if ([NSFileManager.defaultManager moveItemAtURL:loc toURL:dst error:nil]) _pendingFile = dst;
}

- (void)URLSession:(NSURLSession *)s task:(NSURLSessionTask *)t didCompleteWithError:(NSError *)error {
    if (t != _task || _cancelled) return;
    if (!error && _pendingFile) {
        NSURL *f = _pendingFile;
        _pendingFile = nil;
        [self handleDownloadedFile:f];
    } else {
        NSInteger code = [t.response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)t.response statusCode] : 0;
        [self note:[NSString stringWithFormat:@"HTTP %ld %@", (long)code, error.localizedDescription ?: @""]];
        _urlIndex++;           // 換下一個候選網址（例如「原圖」失敗就退回一般網址）
        [self tryCurrent];
    }
}

#pragma mark - 存入照片

- (void)note:(NSString *)msg {
    NSArray<NSURL *> *urls = _items[_index][@"urls"];
    NSString *which = _urlIndex < (NSInteger)urls.count ? urls[_urlIndex].lastPathComponent : @"(image)";
    if (which.length > 28) which = [[which substringToIndex:28] stringByAppendingString:@"…"];
    [_log addObject:[NSString stringWithFormat:@"#%ld #%ld %@\n  %@", (long)_index + 1, (long)_urlIndex + 1, which, msg]];
}

- (void)handleDownloadedFile:(NSURL *)file {
    BOOL isVideo = [_items[_index][@"video"] boolValue];

    if (!_allowPhotos) {                         // 沒有權限：先留著，最後用分享面板
        NSString *ext = isVideo ? @"mp4" : (TPImageExtension(file) ?: @"jpg");
        NSURL *named = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:
                                               [NSString stringWithFormat:@"threads_%@.%@", NSUUID.UUID.UUIDString, ext]]];
        if ([NSFileManager.defaultManager moveItemAtURL:file toURL:named error:nil]) {
            [_leftovers addObject:named]; _saved++;
        } else { _failed++; }
        [self nextItem];
        return;
    }

    if (isVideo) {
        NSURL *mp4 = [NSURL fileURLWithPath:[file.path stringByAppendingPathExtension:@"mp4"]];
        [NSFileManager.defaultManager moveItemAtURL:file toURL:mp4 error:nil];
        [self performSave:^{ [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:mp4]; } completion:^(BOOL ok, NSError *e) {
            [NSFileManager.defaultManager removeItemAtURL:mp4 error:nil];
            if (!ok) [self note:[NSString stringWithFormat:@"save video: %@", e.localizedDescription ?: @"?"]];
            [self itemDone:ok];
        }];
        return;
    }

    // ---- 圖片 ----
    NSString *magic = TPMagicString(file);
    if (_extraReport) {
        UIImage *probe = [UIImage imageWithContentsOfFile:file.path];
        NSDictionary *attr = [NSFileManager.defaultManager attributesOfItemAtPath:file.path error:nil];
        [_savedSizes addObject:[NSString stringWithFormat:@"#%ld %.0fx%.0f %@ %.0f KB", (long)_index + 1,
                                probe.size.width * probe.scale, probe.size.height * probe.scale, magic,
                                [attr fileSize] / 1024.0]];
    }
    NSString *ext = TPImageExtension(file);
    if (ext) {
        NSURL *img = [NSURL fileURLWithPath:[file.path stringByAppendingPathExtension:ext]];
        [NSFileManager.defaultManager moveItemAtURL:file toURL:img error:nil];
        [self performSave:^{ [PHAssetChangeRequest creationRequestForAssetFromImageAtFileURL:img]; } completion:^(BOOL ok, NSError *e) {
            if (ok) { [NSFileManager.defaultManager removeItemAtURL:img error:nil]; [self itemDone:YES]; return; }
            [self note:[NSString stringWithFormat:@"%@ save file: %@", magic, e.localizedDescription ?: @"?"]];
            [self saveDecodedImageAt:img magic:magic];          // 照片 App 不收這個檔案 → 解碼後再存
        }];
    } else {
        [self saveDecodedImageAt:file magic:magic];             // AVIF、WebP 等：解碼後以一般圖片存入
    }
}

/// 把檔案解碼成 UIImage 再存；解不開或存不進去 → 換下一個候選網址
- (void)saveDecodedImageAt:(NSURL *)file magic:(NSString *)magic {
    UIImage *ui = [UIImage imageWithContentsOfFile:file.path];
    [NSFileManager.defaultManager removeItemAtURL:file error:nil];
    NSData *jpeg = TPJPEGData(ui);
    if (!jpeg) {
        [self note:[NSString stringWithFormat:@"%@ can't decode", magic]];
        [self tryNextURL];
        return;
    }
    [self saveJPEGData:jpeg completion:^(BOOL ok, NSError *e) {
        if (ok) { [self itemDone:YES]; return; }
        [self note:[NSString stringWithFormat:@"%@ save jpeg: %@", magic, e.localizedDescription ?: @"?"]];
        [self tryNextURL];
    }];
}

- (void)saveJPEGData:(NSData *)jpeg completion:(void (^)(BOOL ok, NSError *e))completion {
    [self performSave:^{
        PHAssetCreationRequest *r = [PHAssetCreationRequest creationRequestForAsset];
        [r addResourceWithType:PHAssetResourceTypePhoto data:jpeg options:nil];
    } completion:completion];
}

- (void)tryNextURL {
    if (_cancelled) return;
    _urlIndex++;
    [self tryCurrent];        // 網址都用完時，tryCurrent 會改存畫面上那張，或記為失敗
}

/// 只用在「畫面上那張」這種沒有後備的存檔
- (void)saveImage:(UIImage *)image {
    NSData *jpeg = TPJPEGData(image);
    if (!jpeg) { [self note:@"shown image: can't encode"]; [self itemDone:NO]; return; }
    [self saveJPEGData:jpeg completion:^(BOOL ok, NSError *e) {
        if (!ok) [self note:[NSString stringWithFormat:@"save shown image: %@", e.localizedDescription ?: @"?"]];
        [self itemDone:ok];
    }];
}

- (void)itemDone:(BOOL)ok {
    if (_cancelled) return;
    if (ok) _saved++; else _failed++;
    [self nextItem];
}

- (void)performSave:(void (^)(void))changes completion:(void (^)(BOOL ok, NSError *e))completion {
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:changes completionHandler:^(BOOL ok, NSError *e) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self->_cancelled) return;
            completion(ok, e);
        });
    }];
}
@end
