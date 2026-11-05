#requires -Version 5.1
<#
.SYNOPSIS
  Standalone Windows script for the remaining Metrolist Kilo tests (Stage 2).
  It talks to the phone through adb only; Kilo does not need to be running.

.DESCRIPTION
  Tests:
    1. Multi-click OFF: single click is immediate; custom mapping is bypassed.
    2. Click window 250 ms vs 700 ms (two clicks with ~350 ms gap).
    3. Settings defaults persist after an app restart.
    4. Optional phone reboot persistence (-Reboot).
    5. Stage 1 idle regression on the home screen (10 s, <30 frames, <5% CPU).
    6. Release APK install / launch / headset settings page (-ReleaseApk or auto-detect).
  Real Bluetooth headset checks are printed as a manual checklist at the end.

  The script changes in-app headset settings and restores the defaults at the end.
  It never clears app data.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\kilo_remaining_tests.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\kilo_remaining_tests.ps1 `
      -ReleaseApk app\build\outputs\apk\foss\release\app-foss-arm64-v8a-release.apk -Reboot
#>

[CmdletBinding()]
param(
    [string]$Package = 'com.metrolist.music.debug',
    [string]$ReleasePackage = 'com.metrolist.music.kilo',
    [string]$ReleaseApk = '',
    [string]$Adb = 'adb',
    [switch]$SkipIdle,
    [switch]$SkipRelease,
    [switch]$Reboot
)

$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ResultDir = Join-Path $RepoRoot 'test-results'
New-Item -ItemType Directory -Force -Path $ResultDir | Out-Null
$ResultFile = Join-Path $ResultDir ('remaining-tests-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')
$script:Results = New-Object 'System.Collections.Generic.List[object]'

function Write-Log {
    param([string]$Message)
    Write-Host $Message
    Add-Content -LiteralPath $ResultFile -Value $Message -Encoding UTF8
}

function Add-TestResult {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    $script:Results.Add([pscustomobject]@{ Name = $Name; Ok = $Ok; Detail = $Detail }) | Out-Null
    $mark = if ($Ok) { 'PASS' } else { 'FAIL' }
    Write-Log ('[{0}] {1}{2}' -f $mark, $Name, $(if ($Detail) { ' :: ' + $Detail } else { '' }))
}

function Invoke-Adb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$AdbArgs)
    & $Adb @AdbArgs 2>&1
}

function Assert-Device {
    $devices = (Invoke-Adb devices) -join "`n"
    if ($devices -notmatch '(?m)\sdevice\s*$') {
        throw "No adb device. Connect the phone and enable USB/wireless debugging."
    }
}

function Get-ScreenSize {
    $out = (Invoke-Adb shell wm size) -join "`n"
    $matches2 = [regex]::Matches($out, '(\d{3,5})x(\d{3,5})')
    if ($matches2.Count -eq 0) { return @(1220, 2712) }
    $last = $matches2[$matches2.Count - 1]
    return @([int]$last.Groups[1].Value, [int]$last.Groups[2].Value)
}

function Get-UiXml {
    $remote = '/sdcard/kilo_ui.xml'
    $local = Join-Path $env:TEMP 'kilo_ui.xml'
    Invoke-Adb shell uiautomator dump $remote | Out-Null
    Invoke-Adb pull $remote $local | Out-Null
    Invoke-Adb shell rm $remote | Out-Null
    if (-not (Test-Path -LiteralPath $local)) { return $null }
    try {
        return [xml]([System.IO.File]::ReadAllText($local, [System.Text.Encoding]::UTF8))
    } catch {
        return $null
    }
}

function Get-UiTexts {
    param($Xml)
    if (-not $Xml) { return @() }
    return @($Xml.SelectNodes('//node') | ForEach-Object { $_.text } | Where-Object { $_ })
}

function Find-TextNode {
    param([string]$Text, [switch]$Last)
    $xml = Get-UiXml
    if (-not $xml) { return $null }
    $nodes = @($xml.SelectNodes('//node') | Where-Object { $_.text -and $_.text.Contains($Text) })
    if ($nodes.Count -eq 0) { return $null }
    if ($Last) { return $nodes[$nodes.Count - 1] }
    return $nodes[0]
}

function Get-NodeBounds {
    param($Node)
    if ($Node -and $Node.bounds -match '\[(\d+),(\d+)\]\[(\d+),(\d+)\]') {
        return @([int]$matches[1], [int]$matches[2], [int]$matches[3], [int]$matches[4])
    }
    return $null
}

function Tap-Node {
    param($Node)
    $b = Get-NodeBounds $Node
    if (-not $b) { return $false }
    $x = [int](($b[0] + $b[2]) / 2)
    $y = [int](($b[1] + $b[3]) / 2)
    Invoke-Adb shell input tap $x $y | Out-Null
    Start-Sleep -Milliseconds 600
    return $true
}

function Tap-Text {
    param([string]$Text, [switch]$Last)
    $node = Find-TextNode $Text -Last:$Last
    if (-not $node) { return $false }
    return Tap-Node $node
}

function Swipe-Up {
    Invoke-Adb shell input swipe ([int]($script:W / 2)) ([int]($script:H * 0.80)) ([int]($script:W / 2)) ([int]($script:H * 0.35)) 300 | Out-Null
    Start-Sleep -Milliseconds 600
}

function Swipe-Down {
    Invoke-Adb shell input swipe ([int]($script:W / 2)) ([int]($script:H * 0.35)) ([int]($script:W / 2)) ([int]($script:H * 0.80)) 300 | Out-Null
    Start-Sleep -Milliseconds 600
}

function Press-Back {
    Invoke-Adb shell input keyevent 4 | Out-Null
    Start-Sleep -Milliseconds 600
}

function Open-App {
    param([string]$Pkg)
    Invoke-Adb shell am start -n "$Pkg/com.metrolist.music.MainActivity" | Out-Null
    Start-Sleep -Seconds 4
}

function Tap-Avatar {
    Invoke-Adb shell input tap ([int]($script:W - 84)) ([int]($script:H * 0.080)) | Out-Null
    Start-Sleep -Milliseconds 800
}

function Go-Home {
    param([string]$Pkg)
    Open-App $Pkg
    for ($i = 0; $i -lt 5; $i++) {
        $xml = Get-UiXml
        $texts = Get-UiTexts $xml
        if (($texts -contains '搜尋') -and ($texts -contains '媒體庫')) { return }
        Press-Back
    }
    Invoke-Adb shell input tap ([int]($script:W * 0.145)) ([int]($script:H * 0.885)) | Out-Null
    Start-Sleep -Seconds 2
}

function Ensure-HeadsetSettings {
    for ($i = 0; $i -lt 14; $i++) {
        $xml = Get-UiXml
        if (-not $xml) { Start-Sleep -Milliseconds 800; continue }
        $texts = Get-UiTexts $xml

        if ($texts -contains '啟用多擊控制' -or $texts -contains '點擊判定時間') { return $true }
        if ($texts -contains '耳機控制') { Swipe-Up; continue }

        if ($texts -contains '切換 Youtube 頻道') {
            Tap-Text '設定' -Last | Out-Null
            Start-Sleep -Milliseconds 900
            continue
        }
        if (($texts -contains 'AI 歌詞翻譯') -or ($texts -contains 'Android Auto')) {
            Tap-Text '播放與音訊' | Out-Null
            Start-Sleep -Milliseconds 900
            continue
        }
        if (($texts -contains '自動電台播放佇列') -or ($texts -contains '固定隨機播放') -or
            ($texts -contains '播放器最大化時保持螢幕常亮')) {
            Swipe-Up
            continue
        }
        if ($texts -contains '首頁') {
            Tap-Avatar
            continue
        }
        Swipe-Up
    }

    Write-Log 'UI automation could not reach the headset settings.'
    Write-Host 'Please open: 設定 -> 播放與音訊 -> 耳機控制, then press Enter.'
    Read-Host | Out-Null
    return $true
}

function Get-SwitchChecked {
    param([string]$NearText)
    $xml = Get-UiXml
    if (-not $xml) { return $null }
    $label = $xml.SelectNodes('//node') | Where-Object { $_.text -and $_.text.Contains($NearText) } | Select-Object -First 1
    if (-not $label) { return $null }
    $lb = Get-NodeBounds $label
    if (-not $lb) { return $null }
    $cy = ($lb[1] + $lb[3]) / 2
    $switches = @($xml.SelectNodes('//node') | Where-Object { $_.checkable -eq 'true' })
    foreach ($sw in $switches) {
        $b = Get-NodeBounds $sw
        if (-not $b) { continue }
        if ([Math]::Abs((($b[1] + $b[3]) / 2) - $cy) -lt 120) {
            return ($sw.checked -eq 'true')
        }
    }
    return $null
}

function Set-ClickWindow {
    param([int]$Ms)
    Ensure-HeadsetSettings | Out-Null
    $xml = Get-UiXml
    if (-not $xml) { Add-TestResult "Set click window $Ms ms" $false 'no UI dump'; return $false }

    $valueLabel = $xml.SelectNodes('//node') | Where-Object { $_.text -and $_.text -match '毫秒' } | Select-Object -First 1
    $seek = $xml.SelectNodes('//node') | Where-Object {
        $_.class -and ($_.class -match 'SeekBar' -or $_.class -match 'Slider')
    } | Select-Object -First 1

    $x1 = [int]($script:W * 0.23)
    $x2 = [int]($script:W * 0.90)
    $y = 0

    if ($seek) {
        $b = Get-NodeBounds $seek
        if ($b) {
            $x1 = $b[0]
            $x2 = $b[2]
            $y = [int](($b[1] + $b[3]) / 2)
        }
    }
    if ($y -eq 0 -and $valueLabel) {
        $b = Get-NodeBounds $valueLabel
        if ($b) { $y = [int]($b[3] + ($script:H * 0.016)) }
    }
    if ($y -eq 0) {
        Write-Host "Cannot locate the click-window slider. Set it to $Ms ms manually, then press Enter."
        Read-Host | Out-Null
    } else {
        $fraction = ($Ms - 250) / 450.0
        $x = [int]($x1 + ($x2 - $x1) * $fraction)
        Invoke-Adb shell input tap $x $y | Out-Null
        Start-Sleep -Milliseconds 800
    }

    $verify = Get-UiXml
    $ok = $false
    if ($verify) {
        $ok = @($verify.SelectNodes('//node') | Where-Object { $_.text -eq "$Ms 毫秒" }).Count -gt 0
    }
    if (-not $ok) {
        Write-Log "Could not verify $Ms ms automatically."
        Write-Host "Please set the click window to $Ms ms in the app, then press Enter."
        Read-Host | Out-Null
        $verify = Get-UiXml
        if ($verify) {
            $ok = @($verify.SelectNodes('//node') | Where-Object { $_.text -eq "$Ms 毫秒" }).Count -gt 0
        }
    }
    Add-TestResult "Set click window $Ms ms" $ok
    return $ok
}

function Set-Action {
    param([string]$Title, [string]$Value)
    Ensure-HeadsetSettings | Out-Null
    if (-not (Tap-Text $Title)) {
        Add-TestResult "Set $Title = $Value" $false 'title not found'
        return $false
    }
    Start-Sleep -Milliseconds 700
    if (-not (Tap-Text $Value)) {
        Press-Back
        Add-TestResult "Set $Title = $Value" $false 'option not found'
        return $false
    }
    Start-Sleep -Milliseconds 800
    Add-TestResult "Set $Title = $Value" $true
    return $true
}

function Get-Playback {
    param([string]$Pkg = $Package)
    $lines = @(Invoke-Adb shell dumpsys media_session)
    $idx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match ('package=' + [regex]::Escape($Pkg))) { $idx = $i; break }
    }
    if ($idx -lt 0) { return [pscustomobject]@{ State = 'UNKNOWN'; Title = 'UNKNOWN' } }

    $end = [Math]::Min($idx + 25, $lines.Count - 1)
    $block = $lines[$idx..$end]
    $state = 'UNKNOWN'
    $title = 'UNKNOWN'
    foreach ($line in $block) {
        if ($line -match '\{state=([A-Z]+)\(') { $state = $matches[1] }
        if ($line -match 'description=([^,]+)') { $title = $matches[1].Trim() }
    }
    return [pscustomobject]@{ State = $state; Title = $title }
}

function Ensure-Paused {
    $p = Get-Playback
    if ($p.State -ne 'PAUSED') {
        Invoke-Adb shell input keyevent 127 | Out-Null
        Start-Sleep -Milliseconds 700
    }
}

function Send-TwoClicks {
    param([int]$GapMs)
    Invoke-Adb shell input keyevent 85 | Out-Null
    Start-Sleep -Milliseconds $GapMs
    Invoke-Adb shell input keyevent 85 | Out-Null
    Start-Sleep -Milliseconds 1300
}

function Get-CpuTicks {
    param([string]$Pid)
    $stat = (Invoke-Adb shell cat "/proc/$Pid/stat") -join ' '
    $fields = $stat -split '\s+'
    if ($fields.Count -lt 15) { return -1 }
    return [int64]$fields[13] + [int64]$fields[14]
}

function Measure-Idle {
    param([string]$Pkg, [int]$Seconds = 10)
    $pid = ((Invoke-Adb shell pidof $Pkg) -join ' ').Trim()
    if (-not $pid) { return $null }
    Invoke-Adb shell dumpsys gfxinfo $Pkg reset | Out-Null
    $t0 = Get-CpuTicks $pid
    Start-Sleep -Seconds $Seconds
    $gfx = (Invoke-Adb shell dumpsys gfxinfo $Pkg) -join "`n"
    $t1 = Get-CpuTicks $pid
    $frames = -1
    if ($gfx -match 'Total frames rendered:\s*(\d+)') { $frames = [int]$matches[1] }
    return [pscustomobject]@{
        Frames = $frames
        CpuTicks = [int64]($t1 - $t0)
        Pid = $pid
    }
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
Assert-Device
$script:W, $script:H = Get-ScreenSize
Write-Log "Metrolist Kilo remaining tests"
Write-Log "Device: $((Invoke-Adb shell getprop ro.product.model) -join '')  Screen: $($script:W)x$($script:H)"
Write-Log "Package: $Package  Release: $ReleasePackage"
Write-Log "Result file: $ResultFile"
Write-Log ''

# 1) Multi-click OFF: immediate single click and custom mapping bypass
Write-Log '--- 1) Multi-click OFF ---'
Ensure-HeadsetSettings | Out-Null
$wasChecked = Get-SwitchChecked '啟用多擊控制'
if ($wasChecked -eq $null) {
    Write-Log 'Could not read the switch state; toggling it once before testing.'
    Tap-Text '啟用多擊控制' | Out-Null
    Start-Sleep -Milliseconds 800
} elseif ($wasChecked) {
    Tap-Text '啟用多擊控制' | Out-Null
    Start-Sleep -Milliseconds 800
}

$offConfirmed = $false
for ($attempt = 0; $attempt -lt 2; $attempt++) {
    Ensure-Paused
    Invoke-Adb shell input keyevent 85 | Out-Null
    Start-Sleep -Milliseconds 150
    $immediate = Get-Playback
    if ($immediate.State -eq 'PLAYING') { $offConfirmed = $true; break }
    Ensure-Paused
    Tap-Text '啟用多擊控制' | Out-Null
    Start-Sleep -Milliseconds 800
}
Add-TestResult 'Multi-click OFF: single click is immediate (<150 ms)' $offConfirmed

$beforeOff = (Get-Playback).Title
Invoke-Adb shell input keyevent 85 85 | Out-Null
Start-Sleep -Milliseconds 1000
$afterOff = Get-Playback
$customDoubleApplied = ($beforeOff -ne $afterOff.Title)
Add-TestResult 'Multi-click OFF: custom double-click mapping is bypassed' (-not $customDoubleApplied) "before=$beforeOff after=$($afterOff.Title)"
Ensure-Paused

# Restore multi-click ON for the remaining tests.
if ($offConfirmed) {
    Tap-Text '啟用多擊控制' | Out-Null
    Start-Sleep -Milliseconds 800
} elseif ((Get-SwitchChecked '啟用多擊控制') -eq $false) {
    Tap-Text '啟用多擊控制' | Out-Null
    Start-Sleep -Milliseconds 800
}

# 2) Click window boundaries
Write-Log '--- 2) Click window 250 / 700 ms ---'
Set-ClickWindow 250 | Out-Null
Ensure-Paused
$before250 = (Get-Playback).Title
Send-TwoClicks 300
$after250 = (Get-Playback).Title
Add-TestResult '250 ms window splits a ~350 ms double click' ($before250 -eq $after250) "before=$before250 after=$after250"
Ensure-Paused

Set-ClickWindow 700 | Out-Null
Ensure-Paused
$before700 = (Get-Playback).Title
Send-TwoClicks 300
$after700 = (Get-Playback).Title
Add-TestResult '700 ms window combines a ~350 ms double click' ($before700 -ne $after700) "before=$before700 after=$after700"
Ensure-Paused
Set-ClickWindow 400 | Out-Null

# 3) Restore defaults and verify persistence after app restart
Write-Log '--- 3) App restart persistence ---'
Set-Action '雙擊動作' '下一首' | Out-Null
Set-Action '三擊動作' '上一首' | Out-Null
Set-Action '長按動作' '關閉' | Out-Null
Start-Sleep -Seconds 2

Invoke-Adb shell am force-stop $Package | Out-Null
Start-Sleep -Seconds 1
Open-App $Package
Start-Sleep -Seconds 4
Ensure-HeadsetSettings | Out-Null
$ui = Get-UiXml
$texts = Get-UiTexts $ui
$has400 = $texts -contains '400 毫秒'
$hasNext = $texts -contains '下一首'
$hasPrevious = $texts -contains '上一首'
$hasOff = $texts -contains '關閉'
Add-TestResult 'Settings persist after app restart' ($has400 -and $hasNext -and $hasPrevious -and $hasOff) "400=$has400 next=$hasNext previous=$hasPrevious off=$hasOff"

$prefsPath = ((Invoke-Adb shell run-as $Package find files -name '*.preferences_pb') -join '').Trim()
if ($prefsPath) {
    $keys = (Invoke-Adb shell run-as $Package grep -a -o 'headset[A-Za-z]*' $prefsPath) -join ','
    Write-Log "DataStore keys: $keys"
}

# 4) Stage 1 idle regression
if (-not $SkipIdle) {
    Write-Log '--- 4) Stage 1 idle regression ---'
    Go-Home $Package
    Start-Sleep -Seconds 18

    $found = $false
    for ($i = 0; $i -lt 8; $i++) {
        $ui = Get-UiXml
        if ($ui) {
            $texts = Get-UiTexts $ui
            if ($texts -contains '快速存取') { $found = $true; break }
        }
        Swipe-Up
    }
    if (-not $found) {
        for ($i = 0; $i -lt 8; $i++) {
            $ui = Get-UiXml
            if ($ui) {
                $texts = Get-UiTexts $ui
                if ($texts -contains '快速存取') { $found = $true; break }
            }
            Swipe-Down
        }
    }
    Start-Sleep -Seconds 3
    $m = Measure-Idle $Package 10
    if ($m) {
        Add-TestResult 'Home idle frames < 30 / 10 s' ($m.Frames -ge 0 -and $m.Frames -lt 30) "frames=$($m.Frames) cpuTicks=$($m.CpuTicks)"
        Add-TestResult 'Home idle CPU < 5% of one core' ($m.CpuTicks -lt 50) "cpuTicks=$($m.CpuTicks)"
        if ($m.Frames -ge 30) {
            Start-Sleep -Seconds 5
            $m2 = Measure-Idle $Package 10
            if ($m2) {
                Add-TestResult 'Home idle retry frames < 30 / 10 s' ($m2.Frames -ge 0 -and $m2.Frames -lt 30) "frames=$($m2.Frames) cpuTicks=$($m2.CpuTicks)"
            }
        }
    } else {
        Add-TestResult 'Home idle measurement' $false 'app process not running'
    }
}

# 5) Release APK install / launch / settings page
if (-not $SkipRelease) {
    Write-Log '--- 5) Release APK ---'
    $apkPath = $ReleaseApk
    if (-not $apkPath) {
        $candidate = Join-Path $RepoRoot 'app\build\outputs\apk\foss\release\app-foss-arm64-v8a-release.apk'
        if (Test-Path -LiteralPath $candidate) { $apkPath = $candidate }
    }
    if ($apkPath -and (Test-Path -LiteralPath $apkPath)) {
        $install = (Invoke-Adb install -r $apkPath) -join "`n"
        Add-TestResult 'Release APK installs' ($install -match 'Success') $install.Trim()
        if ($install -match 'Success') {
            Open-App $ReleasePackage
            Start-Sleep -Seconds 5
            Ensure-HeadsetSettings | Out-Null
            $ui = Get-UiXml
            $texts = Get-UiTexts $ui
            $hasGroup = $texts -contains '耳機控制' -or $texts -contains '啟用多擊控制'
            Add-TestResult 'Release APK shows headset settings' $hasGroup
            $shot = Join-Path $ResultDir 'release-headset-settings.png'
            $remoteShot = '/sdcard/kilo_release_settings.png'
            Invoke-Adb shell screencap -p $remoteShot | Out-Null
            Invoke-Adb pull $remoteShot $shot | Out-Null
            Invoke-Adb shell rm $remoteShot | Out-Null
            Write-Log "Release screenshot: $shot"
        }
    } else {
        Add-TestResult 'Release APK present' $false 'build it first or pass -ReleaseApk'
        Write-Log 'Build command: $env:METROLIST_APPLICATION_ID="com.metrolist.music.kilo"; .\gradlew.bat :app:assembleFossRelease'
    }
}

# 6) Optional reboot persistence
if ($Reboot) {
    Write-Log '--- 6) Reboot persistence ---'
    Invoke-Adb reboot | Out-Null
    $deadline = (Get-Date).AddSeconds(180)
    $connected = $false
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 3
        $devices = (Invoke-Adb devices) -join "`n"
        if ($devices -match '(?m)\sdevice\s*$') { $connected = $true; break }
    }
    Add-TestResult 'Device reconnects after reboot' $connected
    if ($connected) {
        Start-Sleep -Seconds 20
        $pkgPath = (Invoke-Adb shell pm path $Package) -join ''
        Add-TestResult 'Debug package survives reboot' ($pkgPath -match 'package:') $pkgPath.Trim()
        $prefsPath = ((Invoke-Adb shell run-as $Package find files -name '*.preferences_pb') -join '').Trim()
        if ($prefsPath) {
            $keys = (Invoke-Adb shell run-as $Package grep -a -o 'headset[A-Za-z]*' $prefsPath) -join ','
            Add-TestResult 'Headset settings survive reboot' ($keys -match 'headsetDoubleClickAction') $keys
        } else {
            Add-TestResult 'Headset settings survive reboot' $false 'preferences file not found'
        }
    }
}

# Manual headset checklist
Write-Log ''
Write-Log '--- Manual Bluetooth headset checklist ---'
Write-Log '1. Pair a real Bluetooth headset and play a track.'
Write-Log '2. Single press: play/pause. Double press: next. Triple press: previous.'
Write-Log '3. Standard next/previous/seek buttons still work.'
Write-Log '4. Disconnect the headset: playback pauses.'
Write-Log '5. Reconnect within the configured window: playback resumes.'
Write-Log '6. Pause manually, then disconnect/reconnect: playback must stay paused.'
Write-Log '7. Reconnect after the window expires: playback must stay paused.'
Write-Log '8. Dedicated voice-assistant key still opens the assistant.'
Write-Log '9. Long press: Google Assistant may intercept it on this ROM; the custom long-press action may not fire.'

Write-Log ''
$failed = @($script:Results | Where-Object { -not $_.Ok })
$passed = @($script:Results | Where-Object { $_.Ok })
Write-Log ("SUMMARY: {0} passed, {1} failed" -f $passed.Count, $failed.Count)
Write-Log "Result file: $ResultFile"

if ($failed.Count -gt 0) { exit 1 }
exit 0
