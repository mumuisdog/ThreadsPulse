#import <Foundation/Foundation.h>

/// 側載相容修正：重新簽名後讓鑰匙圈與 App 群組照常運作。用原本的 Meta 簽名執行時不會啟用。
/// 必須在 Threads 開始使用鑰匙圈之前呼叫（ThreadsPulse 載入時）。
void TPSideloadFixInstall(void);
/// 目前狀態（給除錯提示用）
NSString *TPSideloadFixStatus(void);
/// 這次啟動以來鑰匙圈的呼叫、改寫、錯誤次數（給除錯提示用）
NSString *TPSideloadFixStats(void);
