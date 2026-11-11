#import <UIKit/UIKit.h>

@interface TPDownloader : NSObject
// ---- 取得影片網址 ----
+ (NSURL *)bestURLFromObject:(id)videoObject;
+ (NSURL *)bestURLFromVideoView:(UIView *)view player:(id)playerHint;
+ (NSString *)debugReportForVideoView:(UIView *)view player:(id)playerHint;
+ (void)showReport:(NSString *)text;

// ---- 下載（會顯示進度視窗並存入「照片」）----
/// items 每一項：@{ @"urls": @[候選網址...依序嘗試], @"video": @YES/@NO, @"image": UIImage(選填，圖片全部網址失敗時的備援) }
+ (void)downloadItems:(NSArray<NSDictionary *> *)items;
+ (void)downloadVideoURL:(NSURL *)url;

/// 從資料物件（例如貼文媒體的 GraphQL fragment）的實例變數中，找出最佳的影片／圖片網址
+ (NSURL *)bestVideoURLHarvestedFromObject:(id)obj;
+ (NSURL *)bestImageURLHarvestedFromObject:(id)obj;
/// 從影片畫面本身與往上幾層畫面所持有的資料物件裡找影片網址（由近到遠，找到就停）
+ (NSURL *)bestVideoURLNearView:(UIView *)view;

// ---- 工具 ----
/// 從網址中的「1080x1350」之類字樣推算面積；找不到回傳 1
+ (double)imageAreaFromURL:(NSURL *)url;
/// 下一個下載工作結束時，一併顯示這份除錯報告
+ (void)setPendingReport:(NSString *)report;
/// 附加到上面那份報告（只在除錯提示開啟時記錄）
+ (void)appendPendingReport:(NSString *)report;
+ (id)safeValue:(id)obj key:(NSString *)key;
+ (id)ivarValue:(id)obj name:(NSString *)name;
+ (void)toast:(NSString *)text;
+ (UIViewController *)topViewController;
@end
