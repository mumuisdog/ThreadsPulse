// 側載相容修正：重新簽名後，讓 Threads 的鑰匙圈與 App 群組照常運作
//
// Threads 原本的權限（Meta 的 Team ID：MH9GU9K5PX）：
//   keychain-access-groups：MH9GU9K5PX.platformFamily、MH9GU9K5PX.shared
//   application-groups    ：group.com.burbn.instagram、group.com.facebook.family、group.com.burbn.family
// 重新簽名後 Team ID 改變，這些群組都對不上：
//   - 鑰匙圈：存取指定群組會失敗（errSecMissingEntitlement），登入資料存不進去 → 一直被登出
//   - App 群組：containerURLForSecurityApplicationGroupIdentifier: 回傳 nil → 讀寫共用資料失敗
//
// 修正方式：
//   1. 鑰匙圈：把各個已載入映像檔對 SecItemAdd／CopyMatching／Update／Delete 的呼叫，改接到我們的函式，
//      把指定的存取群組換成這個 App 實際可用的群組。
//   2. App 群組：拿不到群組資料夾時，改用 App 自己資料夾裡的替代資料夾。
// 用原本的 Meta 簽名執行（例如越獄安裝）時，偵測到 Team ID 沒變就完全不啟用。

#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <mach/mach.h>
#import <dlfcn.h>
#import "TPPrefs.h"
#import "TPSideloadFix.h"

static NSString *const kTPOriginalTeam = @"MH9GU9K5PX";

static OSStatus (*orig_SecItemAdd)(CFDictionaryRef, CFTypeRef *);
static OSStatus (*orig_SecItemCopyMatching)(CFDictionaryRef, CFTypeRef *);
static OSStatus (*orig_SecItemUpdate)(CFDictionaryRef, CFDictionaryRef);
static OSStatus (*orig_SecItemDelete)(CFDictionaryRef);

static NSString *gTPAccessGroup;      // 這個 App 實際可用的鑰匙圈群組（例如 ABCDE12345.com.example.threads）
static NSString *gTPFixStatus;        // 給除錯提示看的狀態

// ---- 診斷：記錄這次啟動期間鑰匙圈的讀寫與錯誤次數 ----
static volatile int32_t gTPCalls, gTPRewrites, gTPErrors;
static OSStatus gTPLastError;
static char gTPLastErrorWhere[96];

static void TPRecord(const char *op, CFDictionaryRef query, BOOL rewritten, OSStatus s) {
    __sync_fetch_and_add(&gTPCalls, 1);
    if (rewritten) __sync_fetch_and_add(&gTPRewrites, 1);
    if (s == errSecSuccess || s == errSecItemNotFound) return;
    __sync_fetch_and_add(&gTPErrors, 1);
    gTPLastError = s;
    char group[64] = "-";
    CFTypeRef g = query ? CFDictionaryGetValue(query, kSecAttrAccessGroup) : NULL;
    if (g && CFGetTypeID(g) == CFStringGetTypeID()) CFStringGetCString(g, group, sizeof(group), kCFStringEncodingUTF8);
    snprintf(gTPLastErrorWhere, sizeof(gTPLastErrorWhere), "%s %s", op, group);
}

NSString *TPSideloadFixStats(void) {
    NSMutableString *r = [NSMutableString stringWithFormat:@"calls %d · rewrites %d · errors %d", gTPCalls, gTPRewrites, gTPErrors];
    if (gTPErrors) [r appendFormat:@" (last %d: %s)", (int)gTPLastError, gTPLastErrorWhere];
    return r;
}

#pragma mark - 鑰匙圈

/// 存取群組不是我們能用的 → 換成實際可用的群組
static CFDictionaryRef TPFixQuery(CFDictionaryRef query, CFMutableDictionaryRef *owned) {
    *owned = NULL;
    if (!query || !gTPAccessGroup) return query;
    CFTypeRef group = CFDictionaryGetValue(query, kSecAttrAccessGroup);
    if (!group || CFGetTypeID(group) != CFStringGetTypeID()) return query;
    if (CFEqual(group, (__bridge CFStringRef)gTPAccessGroup)) return query;
    CFMutableDictionaryRef copy = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, query);
    CFDictionarySetValue(copy, kSecAttrAccessGroup, (__bridge CFStringRef)gTPAccessGroup);
    *owned = copy;
    return copy;
}

static OSStatus tp_SecItemAdd(CFDictionaryRef attrs, CFTypeRef *result) {
    CFMutableDictionaryRef owned;
    OSStatus s = orig_SecItemAdd(TPFixQuery(attrs, &owned), result);
    TPRecord("Add", attrs, owned != NULL, s);
    if (owned) CFRelease(owned);
    return s;
}

static OSStatus tp_SecItemCopyMatching(CFDictionaryRef query, CFTypeRef *result) {
    CFMutableDictionaryRef owned;
    OSStatus s = orig_SecItemCopyMatching(TPFixQuery(query, &owned), result);
    TPRecord("Copy", query, owned != NULL, s);
    if (owned) CFRelease(owned);
    return s;
}

static OSStatus tp_SecItemUpdate(CFDictionaryRef query, CFDictionaryRef attrs) {
    CFMutableDictionaryRef owned1, owned2;
    OSStatus s = orig_SecItemUpdate(TPFixQuery(query, &owned1), TPFixQuery(attrs, &owned2));
    TPRecord("Update", query, owned1 != NULL || owned2 != NULL, s);
    if (owned1) CFRelease(owned1);
    if (owned2) CFRelease(owned2);
    return s;
}

static OSStatus tp_SecItemDelete(CFDictionaryRef query) {
    CFMutableDictionaryRef owned;
    OSStatus s = orig_SecItemDelete(TPFixQuery(query, &owned));
    TPRecord("Delete", query, owned != NULL, s);
    if (owned) CFRelease(owned);
    return s;
}

/// 存一筆測試資料再讀回來，取得系統實際指派給這個 App 的預設群組
static NSString *TPDetectAccessGroup(void) {
    NSDictionary *query = @{ (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
                             (__bridge id)kSecAttrAccount: @"ThreadsPulse.accessGroupProbe",
                             (__bridge id)kSecAttrService: @"ThreadsPulse",
                             (__bridge id)kSecReturnAttributes: @YES };
    CFTypeRef result = NULL;
    OSStatus s = orig_SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (s == errSecItemNotFound) s = orig_SecItemAdd((__bridge CFDictionaryRef)query, &result);
    if (s != errSecSuccess || !result) return nil;
    NSDictionary *attrs = (__bridge_transfer NSDictionary *)result;
    id group = [attrs isKindOfClass:[NSDictionary class]] ? attrs[(__bridge id)kSecAttrAccessGroup] : nil;
    return [group isKindOfClass:[NSString class]] ? group : nil;
}

#pragma mark - 改接 C 函式（在每個映像檔的符號指標表裡換掉目標函式的位址）

typedef struct { const char *name; void *replacement; } TPRebinding;
static TPRebinding gTPRebindings[4];
static char *gTPAppPath;              // 「/Threads.app/」：只處理 App 本身的檔案（主程式與 Frameworks），不碰系統框架

/// readOnly：區段位在唯讀的 __DATA_CONST／__AUTH_CONST，寫入前要暫時改成可寫、寫完再改回唯讀
static void TPRebindSection(const struct section_64 *sect, intptr_t slide, BOOL readOnly,
                            const struct nlist_64 *symtab, const char *strtab, const uint32_t *indirect) {
    uint32_t *indices = (uint32_t *)indirect + sect->reserved1;
    void **slots = (void **)((uintptr_t)slide + sect->addr);
    size_t count = sect->size / sizeof(void *);
    for (size_t i = 0; i < count; i++) {
        uint32_t idx = indices[i];
        if (idx == INDIRECT_SYMBOL_ABS || idx == INDIRECT_SYMBOL_LOCAL ||
            idx == (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS)) continue;
        const char *name = strtab + symtab[idx].n_un.n_strx;
        if (name[0] != '_' || strncmp(name, "_SecItem", 8) != 0) continue;
        for (size_t r = 0; r < sizeof(gTPRebindings) / sizeof(gTPRebindings[0]); r++) {
            if (strcmp(name + 1, gTPRebindings[r].name) != 0) continue;
            if (slots[i] == gTPRebindings[r].replacement) break;
            if (!readOnly) { slots[i] = gTPRebindings[r].replacement; break; }   // __DATA 本來就可寫
            vm_address_t page = (vm_address_t)&slots[i] & ~(vm_address_t)(PAGE_SIZE - 1);
            if (vm_protect(mach_task_self(), page, PAGE_SIZE, false,
                           VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY) != KERN_SUCCESS) break;
            slots[i] = gTPRebindings[r].replacement;
            vm_protect(mach_task_self(), page, PAGE_SIZE, false, VM_PROT_READ);
            break;
        }
    }
}

static void TPRebindImage(const struct mach_header *header, intptr_t slide) {
    const struct mach_header_64 *mh = (const struct mach_header_64 *)header;
    if (mh->magic != MH_MAGIC_64) return;

    static const void *selfBase;
    if (!selfBase) { Dl_info me; if (dladdr((void *)TPRebindImage, &me)) selfBase = me.dli_fbase; }
    if ((const void *)mh == selfBase) return;                  // 自己的呼叫要走原本的函式
    Dl_info info;
    if (!gTPAppPath || !dladdr(mh, &info) || !info.dli_fname ||
        !strstr(info.dli_fname, gTPAppPath)) return;          // 路徑可能有或沒有 /private 前綴，所以比對 App 資料夾名稱

    const struct segment_command_64 *linkedit = NULL;
    const struct symtab_command *symtabCmd = NULL;
    const struct dysymtab_command *dysymtabCmd = NULL;
    const struct load_command *lc = (const struct load_command *)(mh + 1);
    for (uint32_t i = 0; i < mh->ncmds; i++, lc = (const struct load_command *)((const char *)lc + lc->cmdsize)) {
        if (lc->cmd == LC_SEGMENT_64 && strcmp(((const struct segment_command_64 *)lc)->segname, SEG_LINKEDIT) == 0)
            linkedit = (const struct segment_command_64 *)lc;
        else if (lc->cmd == LC_SYMTAB) symtabCmd = (const struct symtab_command *)lc;
        else if (lc->cmd == LC_DYSYMTAB) dysymtabCmd = (const struct dysymtab_command *)lc;
    }
    if (!linkedit || !symtabCmd || !dysymtabCmd || !dysymtabCmd->nindirectsyms) return;

    uintptr_t base = (uintptr_t)slide + linkedit->vmaddr - linkedit->fileoff;
    const struct nlist_64 *symtab = (const struct nlist_64 *)(base + symtabCmd->symoff);
    const char *strtab = (const char *)(base + symtabCmd->stroff);
    const uint32_t *indirect = (const uint32_t *)(base + dysymtabCmd->indirectsymoff);

    lc = (const struct load_command *)(mh + 1);
    for (uint32_t i = 0; i < mh->ncmds; i++, lc = (const struct load_command *)((const char *)lc + lc->cmdsize)) {
        if (lc->cmd != LC_SEGMENT_64) continue;
        const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
        if (strncmp(seg->segname, "__DATA", 6) != 0 && strncmp(seg->segname, "__AUTH", 6) != 0) continue;
        BOOL readOnly = strstr(seg->segname, "_CONST") != NULL;
        const struct section_64 *sect = (const struct section_64 *)(seg + 1);
        for (uint32_t j = 0; j < seg->nsects; j++, sect++) {
            uint32_t type = sect->flags & SECTION_TYPE;
            if (type == S_LAZY_SYMBOL_POINTERS || type == S_NON_LAZY_SYMBOL_POINTERS)
                TPRebindSection(sect, slide, readOnly, symtab, strtab, indirect);
        }
    }
}

#pragma mark - App 群組

static IMP orig_containerURL;

/// 拿不到群組資料夾時，改用 App 自己資料夾裡的 Library/ThreadsPulseAppGroups/<群組>
static NSURL *tp_containerURL(id self, SEL _cmd, NSString *group) {
    NSURL *url = ((NSURL *(*)(id, SEL, NSString *))orig_containerURL)(self, _cmd, group);
    if (url || ![group isKindOfClass:[NSString class]] || !group.length) return url;
    NSString *path = [[NSHomeDirectory() stringByAppendingPathComponent:@"Library/ThreadsPulseAppGroups"]
                      stringByAppendingPathComponent:group];
    [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
    return [NSURL fileURLWithPath:path isDirectory:YES];
}

#pragma mark - 安裝

NSString *TPSideloadFixStatus(void) { return gTPFixStatus; }

void TPSideloadFixInstall(void) {
    if (![TPPrefs boolForKey:TPKeySideloadFix]) { gTPFixStatus = @"off"; return; }

    orig_SecItemAdd          = dlsym(RTLD_DEFAULT, "SecItemAdd");
    orig_SecItemCopyMatching = dlsym(RTLD_DEFAULT, "SecItemCopyMatching");
    orig_SecItemUpdate       = dlsym(RTLD_DEFAULT, "SecItemUpdate");
    orig_SecItemDelete       = dlsym(RTLD_DEFAULT, "SecItemDelete");
    if (!orig_SecItemAdd || !orig_SecItemCopyMatching || !orig_SecItemUpdate || !orig_SecItemDelete) {
        gTPFixStatus = @"Security functions not found";
        return;
    }

    NSString *group = TPDetectAccessGroup();
    NSString *team = [group componentsSeparatedByString:@"."].firstObject;
    if (!group.length || !team.length) { gTPFixStatus = @"access group not detected"; return; }
    if ([team isEqualToString:kTPOriginalTeam]) { gTPFixStatus = @"original signature, not needed"; return; }
    gTPAccessGroup = [group copy];

    // 1) 鑰匙圈
    gTPAppPath = strdup([NSString stringWithFormat:@"/%@/", NSBundle.mainBundle.bundlePath.lastPathComponent].fileSystemRepresentation);
    gTPRebindings[0] = (TPRebinding){ "SecItemAdd",          (void *)tp_SecItemAdd };
    gTPRebindings[1] = (TPRebinding){ "SecItemCopyMatching", (void *)tp_SecItemCopyMatching };
    gTPRebindings[2] = (TPRebinding){ "SecItemUpdate",       (void *)tp_SecItemUpdate };
    gTPRebindings[3] = (TPRebinding){ "SecItemDelete",       (void *)tp_SecItemDelete };
    _dyld_register_func_for_add_image(TPRebindImage);         // 已載入的會立即處理一次，之後載入的也會處理

    // 2) App 群組
    Method m = class_getInstanceMethod([NSFileManager class], @selector(containerURLForSecurityApplicationGroupIdentifier:));
    if (m) orig_containerURL = method_setImplementation(m, (IMP)tp_containerURL);

    gTPFixStatus = [NSString stringWithFormat:@"active (%@)", team];
}
