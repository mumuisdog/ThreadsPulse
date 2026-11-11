#import <UIKit/UIKit.h>

UIWindow *TPKeyWindow(void);
UIViewController *TPTopViewController(void);

/// 長按選單的一個項目（自己畫的底部選單，不用系統 UIMenu，避免按鈕被系統動畫隱藏後只剩外框）
@interface TPMenuItem : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic, copy) void (^handler)(void);
+ (instancetype)itemWithTitle:(NSString *)title symbol:(NSString *)symbol handler:(void (^)(void))handler;
@end

/// 插件主題色改變時發出
extern NSString *const TPThemeDidChangeNotification;

@interface TPUI : NSObject
/// 毛玻璃圓形按鈕（影片／圖片上的下載鈕）。tap 為點一下的動作；menuItems 不為空時，長按會跳出底部選單。
+ (UIButton *)circleButtonWithSymbol:(NSString *)symbol
                            diameter:(CGFloat)d
                             onTap:(void (^)(void))tap
                         menuItems:(NSArray<TPMenuItem *> *)menuItems;
/// 插件主題色（設定頁開關、按鈕等）；依「主題配色」設定變化
+ (UIColor *)accent;
/// 圖示用的主題色：深色模式稍亮、淺色模式稍深
+ (UIColor *)accentIcon;
+ (NSInteger)themeCount;
+ (UIColor *)themeColorAtIndex:(NSInteger)i;
/// 主題名稱（英文 key，顯示時經 TPL 翻譯）
+ (NSString *)themeNameAtIndex:(NSInteger)i;
+ (void)hapticLight;
+ (void)hapticSuccess;
+ (void)hapticError;
@end
