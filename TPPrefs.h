#import <Foundation/Foundation.h>

// ---- 布林設定 ----
extern NSString *const TPKeyBlockAds;        // 去廣告
extern NSString *const TPKeyStripTracking;   // 移除網址追蹤碼
extern NSString *const TPKeyShowDownloadBtn; // 下載按鈕（貼文上的批次下載、全螢幕檢視的單張／單支下載）
extern NSString *const TPKeyDebugToast;      // 除錯提示
extern NSString *const TPKeyOriginalAvatar;  // 大頭貼從網頁版取得原圖
extern NSString *const TPKeyOriginalImage;   // 圖片嘗試下載原始大小
extern NSString *const TPKeyClipboardLinks;  // 偵測剪貼簿裡的連結
extern NSString *const TPKeyConfirmLike;     // 按讚前確認
extern NSString *const TPKeyHideFollowSuggest; // 隱藏自動跳出的「追蹤對象建議」
extern NSString *const TPKeyNoAutoplay;       // 停用動態影片自動播放
extern NSString *const TPKeyHideFeedSuggest;  // 隱藏動態裡的推薦帳號卡片
extern NSString *const TPKeyBlockScreenshotDetect; // 停用截圖偵測
extern NSString *const TPKeyBlockAnalytics;  // 阻擋分析回傳
extern NSString *const TPKeyExternalBrowser; // 連結用外部瀏覽器開啟
extern NSString *const TPKeyHideIGButton;    // 隱藏個人檔案的 Instagram 按鈕
extern NSString *const TPKeyHomeLongPress;   // 長按首頁標籤開啟設定
extern NSString *const TPKeyTheme;           // 插件主題配色（0 珊瑚 … 5 琥珀）
extern NSString *const TPKeySideloadFix;     // 側載相容修正（重新簽名後的鑰匙圈／App 群組）
extern NSString *const TPKeyCopyProfile;     // 個人檔案長按可複製用戶名稱／個人簡介
extern NSString *const TPKeyPinTabBar;       // 固定底部標籤列（捲動時不隱藏）
extern NSString *const TPKeyKeepFeed;        // 回到 Threads 時保留首頁動態位置
extern NSString *const TPKeyNoPullRefresh;   // 停用首頁下拉重新整理
extern NSString *const TPKeyTabNoScrollTop;  // 點首頁標籤不捲回頂端
extern NSString *const TPKeyTabNoRefresh;    // 點首頁標籤不重新整理

// ---- 選項設定（整數）----
extern NSString *const TPKeyPlaySpeed;       // 0:1x 1:1.25x 2:1.5x 3:2x
extern NSString *const TPKeyExactTime;       // 0:相對時間 1:日期+時間 2:完整(含秒)
extern NSString *const TPKeyClipboardMode;   // 0:詢問 1:自動開啟
extern NSString *const TPKeyBannerPosition;  // 0:上方 1:中間 2:下方
extern NSString *const TPKeyKeepFeedLimit;   // 0:10 分鐘 1:30 分鐘 2:不限時間

@interface TPPrefs : NSObject
+ (BOOL)boolForKey:(NSString *)key;
+ (void)setBool:(BOOL)value forKey:(NSString *)key;
+ (NSInteger)integerForKey:(NSString *)key;
+ (void)setInteger:(NSInteger)value forKey:(NSString *)key;
+ (void)resetAll;

/// 匯出／匯入（備份用）
+ (NSData *)exportJSONData;
/// 回傳實際套用的設定數量；格式錯誤回傳 -1
+ (NSInteger)importJSONData:(NSData *)data;
@end
