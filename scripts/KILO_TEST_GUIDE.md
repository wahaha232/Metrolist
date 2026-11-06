# Metrolist Kilo — 測試需知（另一台電腦接續）

最後更新：2026-11-06  
分支：`stage2-bluetooth`  
套件：`com.metrolist.music.kilo`  
目前安裝版本：13.7.0 (153)，**Android Debug 簽章**（內部測試版）

---

## 0. 這份文件在做什麼

`scripts/kilo_release_checks.ps1` 是一支 Windows PowerShell 測試腳本，只透過 `adb` 操作手機，不需要 Kilo、Android Studio 或原始碼就能測已安裝的 App。

它會自動跑：

- Release APK 檢查：檔案、SHA-256、applicationId、版本、簽章。
- Release APK 安裝 / 啟動 / 「耳機控制」設定頁。
- 250ms / 700ms 點擊視窗邊界（兩次點擊間隔約 350ms）。
- 多擊 ON / OFF 的單擊反應差異。
- App force-stop 後重啟，設定是否保留。
- 首頁閒置 10 秒（目標：<30 幀、<5% 單核 CPU）。

最後會進入**實體藍牙耳機互動 checklist**（可跳過），逐項詢問 PASS / FAIL / SKIP，並把結果寫到 `test-results/release-checks-*.txt`。

腳本**不會**清除 App 資料，也不會改程式碼；它會暫時修改耳機設定，結束時還原成：

- 啟用多擊控制：開
- 點擊判定時間：400ms
- 雙擊動作：下一首
- 三擊動作：上一首
- 長按動作：關閉

---

## 1. 最快開始（只測已安裝的 App）

需求：

- Windows 10 / 11
- PowerShell 5.1（Windows 內建）
- Android platform-tools，`adb` 在 PATH 或稍後用 `-Adb` 指定
- 手機已安裝 `com.metrolist.music.kilo`

步驟：

1. 手機開啟開發者選項 → USB 偵錯（或無線偵錯），接上電腦。
2. 確認 `adb devices` 顯示 `device`，不是 `offline` 或 `unauthorized`。
3. 下載 BAT（只需這一個檔，會自動下載 PS1）：
   <https://raw.githubusercontent.com/wahaha232/Metrolist/stage2-bluetooth/scripts/run_kilo_release_checks.bat>
4. 把 BAT 放在任意資料夾，雙擊執行。
5. 若只是自己用、不想看到簽章/版本 FAIL：
   ```bat
   run_kilo_release_checks.bat -SkipReleaseGates
   ```
6. 想跑實體耳機 checklist：**不要**加 `-SkipManual`，照畫面提示操作。

也可以直接跑 PowerShell：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\kilo_release_checks.ps1 -SkipReleaseGates
```

腳本與 BAT 的 GitHub 位置：

- <https://github.com/wahaha232/Metrolist/blob/stage2-bluetooth/scripts/run_kilo_release_checks.bat>
- <https://github.com/wahaha232/Metrolist/blob/stage2-bluetooth/scripts/kilo_release_checks.ps1>

---

## 2. 測試前必須確認

- App 已安裝且可正常開啟：`com.metrolist.music.kilo`。
- 已登入帳號，首頁／媒體庫有內容（腳本會找「快速存取」；找不到會警告，但仍會量目前首頁）。
- App 介面語言是**繁體中文**。腳本用文字比對「播放與音訊」「耳機控制」「啟用多擊控制」等字串。
- 手機解鎖、不要在分割畫面／子母畫面，螢幕逾時至少 10 分鐘。
- 播放佇列至少 2 首（邊界測試會切換歌曲）。
- 測試開始前先按暫停；腳本會自行處理，但先暫停比較穩。
- 測試中不要碰手機，UI 自動化才不會被打斷。
- 實體耳機已配對；測「超過時間窗不恢復」前，先把 **斷線後恢復時間窗** 設成 **1 分鐘**，不然要等 10 分鐘。

---

## 3. 自動項目與判定

| 項目 | 通過條件 |
|---|---|
| Release APK exists | 指定或自動找到 `app-foss-arm64-v8a-release.apk` |
| ApplicationId | `com.metrolist.music.kilo` |
| Version bump | versionCode > 153 或 versionName ≠ 13.7.0 |
| Signing | 不是 `CN=Android Debug` |
| Install | `adb install -r` 回傳 `Success` |
| Headset settings page | 找得到「啟用多擊控制」 |
| 250ms boundary | 約 350ms 的兩次點擊**不換歌** |
| 700ms boundary | 約 350ms 的兩次點擊**換下一首** |
| ON/OFF response | OFF 的單擊反應比 ON（700ms）至少快 150ms |
| Restart persistence | 重啟後仍為 400ms／下一首／上一首／關閉 |
| Home idle frames | 10 秒 < 30 幀 |
| Home idle CPU | 10 秒 < 50 ticks（<5% 單核） |

---

## 4. 實體藍牙耳機 checklist（人工）

腳本會逐項問 `PASS? [y/n/s]`：`y` = PASS、`n` = FAIL、`s` = SKIP。

1. 單擊：播放 / 暫停。
2. 雙擊：下一首（預設）。
3. 三擊：上一首（預設）。
4. 標準 NEXT / PREVIOUS / PLAY / PAUSE / FAST_FORWARD / REWIND 仍正常。
5. 斷線：播放暫停。
6. 斷線當下正在播放，時間窗內重連：恢復播放。
7. 手動暫停後再斷線／重連：**不應**播放。
8. 超過時間窗才重連：**不應**播放（建議先把時間窗設 1 分鐘）。
9. 專用語音助理鍵：開啟助理。
10. 長按：不要被當成單擊。這台 ROM 的 Google 助理可能先攔截長按，屬系統行為，照實際情況記錄。

建議加測（腳本未自動涵蓋）：

- 螢幕關閉、App 在背景時，單／雙／三擊是否正常。
- 手機重啟後設定是否保留（腳本加 `-Reboot` 可測）。
- 關閉「啟用多擊控制」後，雙擊是否走 Media3 預設 double-tap 換歌；確認這是否符合你的使用習慣。

---

## 5. 參數

```text
-Package <id>            預設 com.metrolist.music.kilo
-Apk <path>              指定 release APK；不給就自動找 build\outputs\apk\foss\release\app-foss-arm64-v8a-release.apk
-Adb <path>              指定 adb.exe
-SkipInstall             不重新安裝 APK，只測目前已安裝的 App
-SkipIdle                跳過首頁閒置量測
-SkipManual              跳過實體耳機 checklist（無人值守時使用）
-SkipReleaseGates        跳過簽章與版本檢查
-AllowDebugSignature     允許 debug 簽章（只顯示 WARN，不 FAIL）
-Reboot                  測手機重啟後設定是否保留（會重開機，約 3 分鐘）
```

常用組合：

```bat
:: 只測目前已安裝的 App，跳過 release gate 與手動 checklist
run_kilo_release_checks.bat -SkipInstall -SkipReleaseGates -SkipManual

:: 完整 release 檢查（APK 是 debug 簽章時加 -AllowDebugSignature）
run_kilo_release_checks.bat -Apk path\to\app-foss-arm64-v8a-release.apk -AllowDebugSignature

:: 測重開機持久化
run_kilo_release_checks.bat -SkipReleaseGates -SkipManual -Reboot
```

---

## 6. 結果與判讀

- 結果檔：`test-results/release-checks-YYYYMMDD-HHmmss.txt`
- 截圖：`test-results/release-headset-settings.png`
- 離開碼：`0` = 全部 PASS；`1` = 有 FAIL。
- `[WARN]` 不算失敗，例如找不到 apksigner、找不到「快速存取」、APK 是 debug 簽章但加了 `-AllowDebugSignature`。
- UI 自動化失敗時：
  - 互動模式：會請你手動導航到「設定 → 播放與音訊 → 耳機控制」，按 Enter 後繼續。
  - 非互動模式（例如被其他程式呼叫）：直接標記 FAIL，不會卡住。

**目前這顆 APK 的預期結果**：

- 「Release APK is not debug-signed」會 FAIL，因為目前是 `CN=Android Debug`。自己測試可加 `-AllowDebugSignature` 或 `-SkipReleaseGates`。
- 「Version bumped beyond 13.7.0 (153)」會 FAIL，因為版本還沒 bump。自己測試可加 `-SkipReleaseGates`。
- 「快速存取 was not found」可能出現 WARN；這是首頁推薦內容變動，不一定是 bug。

---

## 7. 另一台電腦從原始碼建置

需求：

- JDK 21（本機原本是 `D:\Android\jdk-21`）
- Android SDK 37（`compileSdk = 37`）
- 已連接的手機

```bash
git clone https://github.com/wahaha232/Metrolist.git
cd Metrolist
git checkout stage2-bluetooth
```

Windows PowerShell：

```powershell
$env:JAVA_HOME = 'C:\path\to\jdk-21'
$env:PATH = "$env:JAVA_HOME\bin;$env:PATH"
$env:METROLIST_APPLICATION_ID = 'com.metrolist.music.kilo'
$env:METROLIST_APP_NAME = 'Metrolist Kilo'

.\gradlew.bat :app:assembleFossRelease --console=plain
adb install -r app\build\outputs\apk\foss\release\app-foss-arm64-v8a-release.apk
```

注意：

- `*.apk` 在 `.gitignore` 內，GitHub 上沒有 APK；要馬自己建置，要馬從原本電腦的 `app\build\outputs\apk\foss\release\` 或 `dist\` 複製過來。
- 沒有設定 `STORE_PASSWORD` 等 release keystore 變數時，Gradle 會用 **debug key** 簽章。這不影響功能測試，但正式發佈前必須換成 release keystore。
- 版本號目前是 13.7.0 (153)；正式發佈前應 bump。

---

## 8. 疑難排解

**`adb devices` 顯示 offline / unauthorized**

- 手機解鎖，重新插拔 USB，或在開發者選項撤銷 USB 偵錯後重新授權。
- 無線 ADB：`adb connect <phone-ip>:5555`，確認同一個 Wi-Fi。
- 不需要時先 `adb kill-server` 再 `adb start-server`。

**腳本停在 UI 自動化**

- 確認介面語言是繁體中文。
- 手動導航到「設定 → 播放與音訊 → 耳機控制」，按 Enter。
- 不要在測試中滑動或切換 App。

**slider 沒設到指定毫秒數**

- 腳本會用 SeekBar 的實際寬度與內縮值點擊，並重試；若仍失敗，手動把 slider 拉到 250 / 700 / 400ms，再按 Enter（互動模式）。

**找不到「快速存取」**

- 首頁推薦內容會變動；腳本會警告並量目前首頁。只要 10 秒 <30 幀、CPU <5% 仍算通過。

**release 版本的 DataStore / run-as 失敗**

- Release APK 不是 debuggable，`run-as` 會失敗；腳本已忽略，不影響 UI 持久化檢查。
- 要看 DataStore key，請用 debug 版或 root。

**測試結果沒有寫入**

- 確認資料夾可寫入；結果會在 `test-results\`。
- 如果在 repo 的 `scripts\` 裡執行，結果會在 repo 根目錄的 `test-results\`；如果把 BAT 下載到別的資料夾，結果會在該資料夾的上層 `test-results\`。

---

## 9. 目前狀態（2026-11-06）

已通過：

- Stage 2 release APK 安裝、啟動、設定頁顯示。
- 250ms 拆分、700ms 合併（手動實測）。
- App force-stop 後重啟，設定保留。
- 首頁閒置 10 秒：0 幀、0.3% 單核 CPU。

待測：

- 實體藍牙耳機 checklist（第 4 節）。
- 手機重啟後設定保留（`-Reboot`）。
- 關閉多擊後的單擊即時反應（release 曾量到約 360ms，需再確認）。
- 關閉多擊後雙擊走 Media3 預設 double-tap 換歌，是否符合需求。
- 正式簽章與版本號 bump（若之後要發佈）。

---

## 10. 回報時請附上

- `test-results/release-checks-*.txt` 內容。
- 實體耳機 checklist 的答案（或截圖）。
- 手機型號、Android 版本、耳機型號。
- 任何 FAIL 的畫面截圖。
