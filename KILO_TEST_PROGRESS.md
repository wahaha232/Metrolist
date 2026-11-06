# Metrolist Kilo — 測試進度與交接

最後更新：2026-11-06（Stage 2 release 已建置並完成大部分回歸）
測試機：POCO X6 Pro 5G（2311DRK48G）、Android 16、480dpi、120Hz
原始碼：`D:\Claude\YPlayer\metrolist`（本機）
GitHub fork：`wahaha232/Metrolist`
分支：
- `stage1-performance` — `c3b80ec47`（效能修正）
- `stage2-bluetooth` — `58aa15dff`（藍牙耳機控制；包含 Stage 1）

---

## 目前狀態（2026-11-06）

- Stage 2 release APK 已於 2026-11-05 17:41 建置完成，2026-11-06 安裝到 `com.metrolist.music.kilo` 並驗證。
- 設定頁「耳機控制」正常顯示；預設 400ms、雙擊下一首、三擊上一首、長按關閉。
- 已通過：250ms 拆分、700ms 合併、App 重啟後設定保留、首頁閒置 10 秒 0 幀 / 0.3% CPU。
- 尚未完成：實體藍牙耳機手動測試、正式簽章、版本號 bump、dist 打包與文件更新。
- **注意**：目前 release APK 是 **Android Debug** 簽章，版本仍是 13.7.0 (153)，不可直接當正式版發佈。
- 下一步測試腳本：`scripts/kilo_release_checks.ps1`（Windows + adb，含實體耳機 checklist）。
- 測試需知（另一台電腦接續）：`scripts/KILO_TEST_GUIDE.md`。

---

## Stage 1：效能修正（已完成）

### 真正的 P0 根因
首頁「快速存取」區塊的 `RandomizeGridItem` 一直 compose 一個
`Modifier.alpha(0)` 的 Material3 `LoadingIndicator`。它完全透明，但動畫持續執行，
造成首頁閒置時約 60fps 的隱形重繪。

### 量測（`dumpsys gfxinfo` + `/proc/<pid>/stat`）

| 場景 | 修正前 | 修正後 |
|---|---|---|
| 首頁「快速存取」（含 4 點隨機卡片）閒置 10 秒 | 1244 幀（約 124fps）、1001 ticks（約 100% 單核） | **0 幀、9 ticks（0.9%）** |
| 首頁下一區塊（來自社區）閒置 10 秒 | 1262 幀、610 ticks | **0 幀、5 ticks（0.5%）** |
| 播放→暫停後閒置 10 秒 | 持續重繪 | **0 幀、5 ticks** |
| 媒體庫閒置 10 秒 | 0 幀 | **0 幀、6 ticks（0.6%）** |
| Stage 1 release APK（未登入首頁）閒置 10 秒 | — | **0 幀、1 tick（0.1%）** |

驗收門檻「10 秒 <30 幀、CPU <5%」已達成。

### 已包含的修正
- `ui/component/RandomizeGridItem.kt`：只有 `isLoading || loadingAlpha > 0.01f` 才 compose spinner（根因）。
- `ui/component/Items.kt`：移除 4 處格狀標題的無限 `basicMarquee()`；`ItemThumbnail` 依顯示尺寸請求縮圖。
- `ui/component/SpeedDialGridItem.kt`：用 `BoxWithConstraints` 依實際寬度請求縮圖。
- `App.kt`：圖片快取預設 512→128MB；Timber 只在 debug；啟動時於 IO 刪除舊 `cache/coil3_disk_cache`。
- `widget/MetrolistWidgetManager.kt`：改用 `SingletonImageLoader`；先檢查 Music/Turntable/Playlist 三種 widget ID，全空就不解碼封面。
- `recognition/RecognitionForegroundService.kt`：改用 `SingletonImageLoader`。
- `ui/screens/settings/StorageSettings.kt`：歌曲快取預設 1024→512MB。
- `MainActivity.kt`：動態主題取色解碼降到 64×64（原本已在 IO 與依網址快取）。
- `ui/player/MiniPlayer.kt`：舊版迷你播放器 marquee 改為只跑 1 次。
- `app/build.gradle.kts`：ABI split（arm64 / armeabi-v7a / x86 / x86_64 + universal）；本機 release 在沒有 `STORE_PASSWORD` 時用 debug key 簽章。

### 縮圖尺寸（480dpi，1.25x，64px 級距）
- 48dp 列表縮圖：**544×544 → 192×192**
- 104dp 格狀：**544 → 448px**
- 128dp 格狀：**544 → 512px**
- 網址本身帶尺寸，Coil 記憶體／磁碟快取 key 會不同。

### Stage 1 交付 APK（本機 `D:\Claude\Metrolist\dist`，未進 git）
- `Metrolist-Kilo-13.7.0-arm64-v8a-release.apk`（23.46MB）
  SHA-256 `1AA258CEB94443F138A996816C5CE0BC9105AE31FEA7978D53BAB177FB31BC16`
- `Metrolist-Kilo-13.7.0-universal-release.apk`（25.9MB）
  SHA-256 `50537D79AFDCFB10026A99F172C6154438F47735BD0734B923B4BBB32BEC88D8`
- applicationId：`com.metrolist.music.kilo`；label：`Metrolist Kilo`；version 13.7.0 (153)
- 含 `assets/dexopt/baseline.prof` 與 `profileinstaller`；R8 使用 AGP 9.3 預設 full mode。

---

## Stage 2：藍牙耳機控制（功能完成，測試部分完成）

### 實作
- `playback/HeadsetClickDetector.kt`：純 Kotlin 點擊累積器。
- `playback/HeadsetMediaButtonController.kt`：Android Handler 排程 400ms 視窗與長按。
- `playback/BluetoothResumePolicy.kt`：重連恢復時間窗判斷。
- `playback/MediaLibrarySessionCallback.kt`：覆寫 `onMediaButtonEvent`。
- `playback/MusicService.kt`：記錄藍牙斷線時間；只在「斷線當下正在播放」且「N 分鐘內重連」時恢復。
- `ui/screens/settings/PlayerSettings.kt`：新增「耳機控制」群組。
- `constants/PreferenceKeys.kt`：新增 `Headset*` 設定 key 與 `HeadsetAction`。
- `res/values/metrolist_strings.xml`、`res/values-zh-rTW/metrolist_strings.xml`：新增字串。
- 測試：`HeadsetClickDetectorTest`（9 個案例）、`BluetoothResumePolicyTest`（4 個案例）。

### 已通過
- 單元測試：`./gradlew :app:testFossDebugUnitTest --tests "com.metrolist.music.playback.*"` → 成功。
- adb 實機：
  - 單擊：播放/暫停。
  - 雙擊：下一首（預設）。
  - 三擊：上一首（預設）。
  - 自訂雙擊改「上一首」：實測會上一首。
  - 標準 NEXT / PREVIOUS / PLAY / PAUSE / FAST_FORWARD / REWIND 都正常。
  - `KEYCODE_HEADSETHOOK`（79）單擊正常。
  - 背景＋螢幕關閉：單擊仍可 `PAUSED → PLAYING → PAUSED`。
  - 關閉「啟用多擊控制」：單擊在 150ms 內即 PLAYING（確認無 400ms 延遲）；自訂雙擊/三擊映射不會套用。
  - 設定持久化：DataStore 已寫入 `headsetDoubleClickAction=NEXT`、`headsetTripleClickAction=PREVIOUS`。
  - 設定頁 zh-TW 顯示正常（截圖：`docs/screenshots/headset-settings-zh-tw.png`）。
- 長按：即使自訂長按動作關閉，長按也不會被當成單擊。這台 ROM 的 Google 助理會攔截長按並開啟；助理功能正常，但**自訂長按動作可能不會觸發**。

### 2026-11-06 release 驗證（已完成）

- Stage 2 release APK（`app-foss-arm64-v8a-release.apk`，24.6MB，SHA-256 `1B9089BD53D5300389D4EC449C46CE7750AABD76F5FFAA40229C77C56EE8152E`）安裝成功。
- 設定頁「耳機控制」顯示；`啟用多擊控制` 開關、slider、三個動作選單正常。
- 250ms 視窗：兩次點擊間隔約 350ms → 拆成兩次單擊（不換歌）。
- 700ms 視窗：同樣間隔 → 合成雙擊（下一首）。
- App force-stop 後重啟：400ms / 下一首 / 上一首 / 關閉 全部保留。
- 首頁閒置 10 秒：0 幀、3 ticks（0.3% 單核）。
- 關閉多擊後即時反應：release 上量到約 360ms，與開啟 250ms 視窗相近；量測受 dumpsys 延遲影響，需再確認。關閉後雙擊仍會落到 Media3 內建 double-tap 而換歌。

### 尚未完成（正式發行前）

1. **實體藍牙耳機手動測試**（用 `scripts/kilo_release_checks.ps1` 的 checklist）：
   - 單／雙／三擊是否照預期。
   - 斷線是否暫停；N 分鐘內重連是否恢復。
   - 手動暫停後再斷線，重連**不應**播放。
   - 超過時間窗重連**不應**播放。
   - 專用語音助理鍵；長按（若 Google 助理攔截，屬系統行為）。
2. **正式簽章**：目前 APK 用 Android Debug 憑證；需設定 release keystore（`STORE_PASSWORD` 等），再用 apksigner 驗證。
3. **版本號 bump**：目前 13.7.0 (153)，與 Stage 1 相同；正式版應提高 versionCode/versionName。
4. **dist 打包**：把 Stage 2 arm64 / universal APK 放進 `D:\Claude\Metrolist\dist`，更新 SHA-256 與本文件。
5. （可選）確認關閉多擊後的即時反應，以及 Media3 預設雙擊是否符合「關閉＝兩次單擊」的產品需求。

---

## 在另一台電腦繼續

### 一鍵測試腳本（不需要 Kilo）

**新的 release 驗收腳本**：`scripts/kilo_release_checks.ps1` + `scripts/run_kilo_release_checks.bat`

完整測試需知（需求、參數、疑難排解、回報格式）：[`scripts/KILO_TEST_GUIDE.md`](scripts/KILO_TEST_GUIDE.md)

- Release gate：APK 存在、SHA-256、applicationId、版本、簽章（debug key 會 FAIL，除非 `-AllowDebugSignature`）。
- Release 安裝 / 啟動 / 「耳機控制」頁面。
- 250ms / 700ms 點擊視窗邊界（約 350ms 間隔）。
- 多擊 ON/OFF 單擊反應差異（相對計時）。
- App 重啟後設定持久化。
- 首頁閒置 10 秒（<30 幀、<5% CPU）。
- 實體藍牙耳機互動 checklist（可用 `-SkipManual` 跳過）。
- 可選 `-Reboot`：手機重啟後持久化。

最簡單：下載 `scripts/run_kilo_release_checks.bat` 後直接雙擊（若同目錄沒有 PS1，BAT 會自動下載）。

```bat
run_kilo_release_checks.bat
:: 指定 APK、允許內部 debug 簽章、跳過手動 checklist：
run_kilo_release_checks.bat -Apk app\build\outputs\apk\foss\release\app-foss-arm64-v8a-release.apk -AllowDebugSignature -SkipManual
```

或直接跑 PowerShell：
```powershell
powershell -ExecutionPolicy Bypass -File scripts\kilo_release_checks.ps1
powershell -ExecutionPolicy Bypass -File scripts\kilo_release_checks.ps1 `
  -Apk app\build\outputs\apk\foss\release\app-foss-arm64-v8a-release.apk -AllowDebugSignature -SkipManual
```

結果寫到 `test-results/release-checks-*.txt`。若 UI 自動化失敗，互動模式會請你手動導航後按 Enter；非互動模式會標記失敗。

舊的 `scripts/kilo_remaining_tests.ps1` / `run_kilo_tests.bat` 保留作歷史參考；它的 `$pid`、`grep -o` 與 slider 邊緣點擊問題已在新腳本修正。

### 需求
- JDK 21（本機是 `D:\Android\jdk-21`）
- Android SDK 37（`compileSdk = 37`）
- 已連接的 Android 手機（無線 ADB 亦可）

### 取得程式
```bash
git clone https://github.com/wahaha232/Metrolist.git
cd Metrolist
git checkout stage2-bluetooth
```

### 建置 debug（保留原本帳號資料）
```powershell
$env:JAVA_HOME='<JDK21 路徑>'
$env:PATH="$env:JAVA_HOME\bin;$env:PATH"
.\gradlew.bat :app:assembleFossDebug --console=plain
adb install -r app\build\outputs\apk\foss\debug\app-foss-arm64-v8a-debug.apk
```

### 建置 release（applicationId `com.metrolist.music.kilo`）
```powershell
$env:JAVA_HOME='<JDK21 路徑>'
$env:PATH="$env:JAVA_HOME\bin;$env:PATH"
$env:METROLIST_APPLICATION_ID='com.metrolist.music.kilo'
$env:METROLIST_APP_NAME='Metrolist Kilo'
.\gradlew.bat :app:assembleFossRelease --console=plain
```
輸出：
`app\build\outputs\apk\foss\release\app-foss-arm64-v8a-release.apk`
`app\build\outputs\apk\foss\release\app-foss-universal-release.apk`

> 本機 release 在沒有 `STORE_PASSWORD` 時會用 debug key 簽章；若在 CI 要正式簽章，請設定 release keystore 環境變數。

### 單元測試
```powershell
.\gradlew.bat :app:testFossDebugUnitTest --tests "com.metrolist.music.playback.*" --console=plain
```

### adb 按鍵測試
```powershell
adb shell input keyevent 85          # PLAY_PAUSE（單擊）
adb shell input keyevent 85 85       # 雙擊
adb shell input keyevent 85 85 85    # 三擊
adb shell input keyevent 87          # NEXT
adb shell input keyevent 88          # PREVIOUS
adb shell input keyevent 126         # PLAY
adb shell input keyevent 127         # PAUSE
adb shell input keyevent 90          # FAST_FORWARD
adb shell input keyevent 89          # REWIND
adb shell input keyevent 79          # HEADSETHOOK
adb shell input keyevent --longpress 85
```
查詢目前狀態：
```powershell
adb shell dumpsys media_session | Select-String "state=PlaybackState|metadata:.*description="
```

### Stage 1 回歸量測
1. 開啟 App，停在首頁「快速存取」（含 4 點隨機卡片）。
2. 記下 pid，`dumpsys gfxinfo com.metrolist.music.debug reset`。
3. 等 10 秒，讀 `Total frames rendered` 與 `/proc/<pid>/stat` 的 utime+stime。
4. 目標：**0 幀、CPU <5%**。

---

## 已知限制
- 這台手機的 Google 助理會先攔截耳機長按；自訂長按動作可能不會觸發。助理本身正常。
- 部分耳機的雙擊會直接送 `KEYCODE_MEDIA_NEXT`，而不是兩次 PLAY_PAUSE；這種情況會走標準按鍵，不會經過多擊判定。
- 16:xx 的建置路徑為本機 `D:\Claude\YPlayer\metrolist`；換電腦請用新的 clone。
