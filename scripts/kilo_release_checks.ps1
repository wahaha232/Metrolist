#requires -Version 5.1
<#
.SYNOPSIS
  Metrolist Kilo release acceptance checks (Stage 2 headset controls + Stage 1 regression).

.DESCRIPTION
  Runs on Windows and talks to the phone through adb only. Kilo does not need to be running.

  Automated checks:
    1. Release APK identity, version, SHA-256 and signing certificate.
    2. Release APK install / launch / headset settings page.
    3. Click-window boundaries: 250 ms splits, 700 ms combines a ~350 ms double click.
    4. Multi-click ON vs OFF single-click response (relative timing).
    5. Settings persistence after force-stop + relaunch.
    6. Home idle regression: 10 s, < 30 frames, < 5% of one CPU core.

  Manual check:
    Bluetooth headset checklist (single/double/triple click, disconnect, reconnect,
    manual pause, expired resume window, assistant key, long press). Use -SkipManual
    for unattended runs.

  The script restores 400 ms / NEXT / PREVIOUS / NONE and leaves multi-click enabled.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\kilo_release_checks.ps1

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\kilo_release_checks.ps1 `
      -Apk app\build\outputs\apk\foss\release\app-foss-arm64-v8a-release.apk `
      -AllowDebugSignature -SkipManual

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\kilo_release_checks.ps1 -SkipReleaseGates -SkipIdle
#>

[CmdletBinding()]
param(
    [string]$Package = 'com.metrolist.music.kilo',
    [string]$Apk = '',
    [string]$Adb = 'adb',
    [switch]$SkipInstall,
    [switch]$SkipIdle,
    [switch]$SkipManual,
    [switch]$SkipReleaseGates,
    [switch]$Reboot,
    [switch]$AllowDebugSignature
)

$ErrorActionPreference = 'Continue'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ResultDir = Join-Path $RepoRoot 'test-results'
New-Item -ItemType Directory -Force -Path $ResultDir | Out-Null
$ResultFile = Join-Path $ResultDir ('release-checks-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')
$script:Results = New-Object 'System.Collections.Generic.List[object]'
$script:W = 1220
$script:H = 2712

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

function Add-Warn {
    param([string]$Message)
    Write-Log ('[WARN] ' + $Message)
}

function Invoke-Adb {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$AdbArgs)
    & $Adb @AdbArgs 2>&1
}

function Assert-Device {
    $devices = (Invoke-Adb devices) -join "`n"
    if ($devices -notmatch '(?m)\sdevice\s*$') {
        throw 'No adb device. Connect the phone and enable USB/wireless debugging.'
    }
}

function Get-ScreenSize {
    $out = (Invoke-Adb shell wm size) -join "`n"
    $m = [regex]::Matches($out, '(\d{3,5})x(\d{3,5})')
    if ($m.Count -eq 0) { return @(1220, 2712) }
    $last = $m[$m.Count - 1]
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
        $texts = Get-UiTexts (Get-UiXml)
        if (($texts -contains '首頁') -and ($texts -contains '搜尋') -and ($texts -contains '媒體庫')) {
            Invoke-Adb shell input tap ([int]($script:W * 0.16)) ([int]($script:H * 0.905)) | Out-Null
            Start-Sleep -Seconds 2
            return
        }
        Press-Back
    }
    Open-App $Pkg
    Invoke-Adb shell input tap ([int]($script:W * 0.16)) ([int]($script:H * 0.905)) | Out-Null
    Start-Sleep -Seconds 2
}

function Ensure-HeadsetSettings {
    for ($i = 0; $i -lt 24; $i++) {
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
        if (($texts -contains 'AI 歌詞翻譯') -or ($texts -contains 'Android Auto') -or
            ($texts -contains '儲存和數據') -or ($texts -contains '私隱與安全性')) {
            Tap-Text '播放與音訊' | Out-Null
            Start-Sleep -Milliseconds 900
            continue
        }
        if (($texts -contains '首頁') -and ($texts -contains '媒體庫')) {
            Tap-Avatar
            continue
        }
        if (($texts -contains '音質') -or ($texts -contains '歌曲淡入淡出') -or
            ($texts -contains '標準化音量') -or ($texts -contains '自動電台播放佇列') -or
            ($texts -contains '固定隨機播放') -or ($texts -contains '播放器最大化時保持螢幕常亮') -or
            ($texts -contains '睡眠定時器') -or ($texts -contains '其他')) {
            Swipe-Up
            continue
        }
        Swipe-Up
    }

    if ([Console]::IsInputRedirected) { return $false }
    Write-Log 'UI automation could not reach the headset settings.'
    Write-Host 'Please open: 設定 -> 播放與音訊 -> 耳機控制, then press Enter.'
    Read-Host | Out-Null
    return $true
}

function Ensure-TextVisible {
    param([string]$Text)
    for ($i = 0; $i -lt 6; $i++) {
        if ((Get-UiTexts (Get-UiXml)) -contains $Text) { return $true }
        Swipe-Up
    }
    for ($i = 0; $i -lt 6; $i++) {
        if ((Get-UiTexts (Get-UiXml)) -contains $Text) { return $true }
        Swipe-Down
    }
    return $false
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

function Set-SwitchState {
    param([bool]$Want)
    Ensure-HeadsetSettings | Out-Null
    $state = Get-SwitchChecked '啟用多擊控制'
    if ($state -eq $null) {
        Add-TestResult "Set multi-click $Want" $false 'switch not found'
        return $false
    }
    if ($state -eq $Want) { return $true }
    Tap-Text '啟用多擊控制' | Out-Null
    Start-Sleep -Milliseconds 900
    $state2 = Get-SwitchChecked '啟用多擊控制'
    Add-TestResult "Set multi-click $Want" ($state2 -eq $Want) "was=$state now=$state2"
    return ($state2 -eq $Want)
}

function Get-ClickWindowValue {
    $xml = Get-UiXml
    if (-not $xml) { return $null }
    $node = $xml.SelectNodes('//node') | Where-Object { $_.text -and $_.text -match '^\s*\d+\s*毫秒' } | Select-Object -First 1
    if ($node -and $node.text -match '(\d+)\s*毫秒') { return [int]$matches[1] }
    return $null
}

function Set-ClickWindow {
    param([int]$Ms)
    Ensure-HeadsetSettings | Out-Null
    Set-SwitchState $true | Out-Null

    for ($attempt = 0; $attempt -lt 8; $attempt++) {
        $xml = Get-UiXml
        if (-not $xml) { Start-Sleep -Milliseconds 700; continue }
        $seek = $xml.SelectNodes('//node') | Where-Object { $_.class -and $_.class -match 'SeekBar' } | Select-Object -First 1
        if ($seek) {
            $b = Get-NodeBounds $seek
            if ($b) {
                $inset = [int](($b[2] - $b[0]) * 0.08)
                $left = $b[0] + $inset
                $right = $b[2] - $inset
                $y = [int](($b[1] + $b[3]) / 2)
                $fraction = ($Ms - 250) / 450.0
                $x = [int]($left + ($right - $left) * $fraction)
                Invoke-Adb shell input tap $x $y | Out-Null
                Start-Sleep -Milliseconds 700

                $actual = Get-ClickWindowValue
                if ($actual -eq $Ms) {
                    Add-TestResult "Set click window $Ms ms" $true
                    return $true
                }
                if ($actual -ne $null) {
                    $deltaX = [int](($Ms - $actual) / 450.0 * ($right - $left))
                    $x = [Math]::Min($right, [Math]::Max($left, $x + $deltaX))
                    Invoke-Adb shell input tap $x $y | Out-Null
                    Start-Sleep -Milliseconds 700
                    $actual2 = Get-ClickWindowValue
                    if ($actual2 -eq $Ms) {
                        Add-TestResult "Set click window $Ms ms" $true
                        return $true
                    }
                }
            }
        }
        Swipe-Up
    }

    Add-TestResult "Set click window $Ms ms" $false 'slider not found or value not verified'
    return $false
}

function Set-Action {
    param([string]$Title, [string]$Value)
    Ensure-HeadsetSettings | Out-Null
    if (-not (Ensure-TextVisible $Title)) {
        Add-TestResult "Set $Title = $Value" $false 'row not found'
        return $false
    }
    for ($attempt = 0; $attempt -lt 4; $attempt++) {
        if (-not (Tap-Text $Title)) { Swipe-Up; continue }
        Start-Sleep -Milliseconds 800
        if (Tap-Text $Value -Last) {
            Start-Sleep -Milliseconds 800
            Add-TestResult "Set $Title = $Value" $true
            return $true
        }
        Press-Back
    }
    Add-TestResult "Set $Title = $Value" $false 'option not found'
    return $false
}

function Get-Playback {
    param([string]$Pkg = $Package)
    $lines = @(Invoke-Adb shell dumpsys media_session)
    $idx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match ('package=' + [regex]::Escape($Pkg))) { $idx = $i; break }
    }
    if ($idx -lt 0) { return [pscustomobject]@{ State = 'UNKNOWN'; Title = 'UNKNOWN' } }
    $end = [Math]::Min($idx + 30, $lines.Count - 1)
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
    if ($p.State -ne 'PAUSED' -and $p.State -ne 'UNKNOWN') {
        Invoke-Adb shell input keyevent 127 | Out-Null
        Start-Sleep -Milliseconds 800
    }
}

function Invoke-DeviceScript {
    param([string]$Content)
    $tmp = Join-Path $env:TEMP ('kilo_dev_' + [guid]::NewGuid().ToString('N') + '.sh')
    $remote = '/data/local/tmp/' + [System.IO.Path]::GetFileName($tmp)
    try {
        Set-Content -LiteralPath $tmp -Value $Content -Encoding ASCII
        Invoke-Adb push $tmp $remote | Out-Null
        return @(Invoke-Adb shell sh $remote)
    } finally {
        Invoke-Adb shell rm $remote | Out-Null
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    }
}

function Send-TwoClicks {
    param([double]$GapSeconds = 0.35)
    $script = "input keyevent 85`nsleep $GapSeconds`ninput keyevent 85"
    Invoke-DeviceScript $script | Out-Null
    Start-Sleep -Milliseconds 1600
}

function Measure-SingleClickDelta {
    $script = @'
input keyevent 127
sleep 1.2
echo "U0 $(dumpsys media_session | grep -m1 'state=PlaybackState' | grep -oE 'updated=[0-9]+')"
input keyevent 85
sleep 1.2
echo "U1 $(dumpsys media_session | grep -m1 'state=PlaybackState' | grep -oE 'updated=[0-9]+')"
'@
    $out = Invoke-DeviceScript $script
    $u0 = $null
    $u1 = $null
    foreach ($line in $out) {
        if ($line -match 'U0 updated=(\d+)') { $u0 = [int64]$matches[1] }
        if ($line -match 'U1 updated=(\d+)') { $u1 = [int64]$matches[1] }
    }
    if ($u0 -eq $null -or $u1 -eq $null) { return $null }
    # The on-device script waits 1.2 s between U0 and U1; subtract that fixed wait.
    return [int](($u1 - $u0) - 1200)
}

function Measure-AverageDelta {
    $values = @()
    for ($i = 0; $i -lt 2; $i++) {
        $d = Measure-SingleClickDelta
        if ($d -ne $null) { $values += $d }
        Start-Sleep -Milliseconds 500
    }
    if ($values.Count -eq 0) { return $null }
    return [int](($values | Measure-Object -Average).Average)
}

function Get-CpuTicks {
    param([string]$AppPid)
    $stat = (Invoke-Adb shell cat "/proc/$AppPid/stat") -join ' '
    $fields = $stat -split '\s+'
    if ($fields.Count -lt 15) { return -1 }
    return [int64]$fields[13] + [int64]$fields[14]
}

function Measure-Idle {
    param([string]$Pkg, [int]$Seconds = 10)
    $appPid = ((Invoke-Adb shell pidof $Pkg) -join ' ').Trim()
    if (-not $appPid) { return $null }
    Invoke-Adb shell dumpsys gfxinfo $Pkg reset | Out-Null
    $t0 = Get-CpuTicks $appPid
    Start-Sleep -Seconds $Seconds
    $gfx = (Invoke-Adb shell dumpsys gfxinfo $Pkg) -join "`n"
    $t1 = Get-CpuTicks $appPid
    $frames = -1
    if ($gfx -match 'Total frames rendered:\s*(\d+)') { $frames = [int]$matches[1] }
    return [pscustomobject]@{
        Frames = $frames
        CpuTicks = [int64]($t1 - $t0)
        Pid = $appPid
    }
}

function Find-ApkSigner {
    $candidates = @()
    foreach ($root in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, 'D:\Android\sdk', 'C:\Android\sdk')) {
        if (-not $root) { continue }
        $bt = Join-Path $root 'build-tools'
        if (Test-Path -LiteralPath $bt) {
            $candidates += Get-ChildItem -LiteralPath $bt -Directory -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending |
                ForEach-Object { Join-Path $_.FullName 'apksigner.bat' }
        }
    }
    $cmd = Get-Command apksigner -ErrorAction SilentlyContinue
    if ($cmd) { $candidates += $cmd.Source }
    return ($candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
}

function Find-Aapt {
    $candidates = @()
    foreach ($root in @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, 'D:\Android\sdk', 'C:\Android\sdk')) {
        if (-not $root) { continue }
        $bt = Join-Path $root 'build-tools'
        if (Test-Path -LiteralPath $bt) {
            $candidates += Get-ChildItem -LiteralPath $bt -Directory -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending |
                ForEach-Object { Join-Path $_.FullName 'aapt.exe' }
        }
    }
    $cmd = Get-Command aapt -ErrorAction SilentlyContinue
    if ($cmd) { $candidates += $cmd.Source }
    return ($candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1)
}

function Test-ReleaseGates {
    param([string]$Path)
    if ($SkipReleaseGates) {
        Write-Log 'Release gates skipped (-SkipReleaseGates).'
        return
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        Add-TestResult 'Release APK exists' $false $Path
        return
    }

    $hash = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    Add-TestResult 'Release APK exists' $true $Path
    Write-Log "SHA-256: $hash"

    $signer = Find-ApkSigner
    if ($signer) {
        $cert = (& $signer verify --print-certs $Path 2>&1) -join "`n"
        $isDebug = $cert -match 'CN=Android Debug'
        if ($isDebug) {
            if ($AllowDebugSignature) {
                Add-Warn 'APK is signed with the Android Debug certificate (-AllowDebugSignature).'
            } else {
                Add-TestResult 'Release APK is not debug-signed' $false 'CN=Android Debug'
            }
        } else {
            Add-TestResult 'Release APK is not debug-signed' $true
        }
    } else {
        Add-Warn 'apksigner not found; signing was not checked.'
    }

    $aapt = Find-Aapt
    if ($aapt) {
        $badging = (& $aapt dump badging $Path 2>&1) -join "`n"
        if ($badging -match "package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'") {
            $pkgName = $matches[1]
            $code = [int]$matches[2]
            $name = $matches[3]
            Add-TestResult 'Release APK applicationId' ($pkgName -eq $Package) $pkgName
            $bumped = ($code -gt 153) -or ($name -ne '13.7.0')
            Add-TestResult 'Version bumped beyond 13.7.0 (153)' $bumped "versionCode=$code versionName=$name"
        } else {
            Add-Warn 'aapt could not parse the APK badging.'
        }
    } else {
        Add-Warn 'aapt not found; version was not checked.'
    }
}

function Invoke-ManualHeadsetChecklist {
    Write-Log ''
    Write-Log '--- Manual Bluetooth headset checklist ---'
    if ($SkipManual) {
        Write-Log 'Skipped (-SkipManual).'
        return
    }
    if ([Console]::IsInputRedirected) {
        Write-Log 'Skipped (input is redirected; run interactively to use the manual checklist).'
        return
    }

    Write-Host 'Connect a Bluetooth headset, start a track, then press Enter.'
    Read-Host | Out-Null
    $items = @(
        @{ Name = 'Single press toggles play/pause'; Hint = 'Press the headset button once.' },
        @{ Name = 'Double press goes to the next track'; Hint = 'Press twice quickly (default NEXT).' },
        @{ Name = 'Triple press goes to the previous track'; Hint = 'Press three times quickly (default PREVIOUS).' },
        @{ Name = 'Standard media buttons still work'; Hint = 'NEXT / PREVIOUS / PLAY / PAUSE / FF / REW.' },
        @{ Name = 'Disconnect pauses playback'; Hint = 'Turn the headset off or move it out of range.' },
        @{ Name = 'Reconnect inside the window resumes playback'; Hint = 'Reconnect within 10 minutes.' },
        @{ Name = 'Manual pause stays paused after reconnect'; Hint = 'Pause first, then disconnect and reconnect.' },
        @{ Name = 'Reconnect after the window stays paused'; Hint = 'Set the resume window to 1 minute and wait it out.' },
        @{ Name = 'Voice assistant key opens the assistant'; Hint = 'Use the dedicated assistant button if present.' },
        @{ Name = 'Long press does not fire a single click'; Hint = 'Google Assistant may intercept the long press on this ROM.' }
    )

    foreach ($item in $items) {
        Write-Host ''
        Write-Host ('{0}  ({1})' -f $item.Name, $item.Hint)
        $answer = (Read-Host 'PASS? [y/n/s]').Trim().ToLower()
        switch ($answer) {
            'y' { Add-TestResult $item.Name $true 'manual' }
            'n' { Add-TestResult $item.Name $false 'manual' }
            default { Write-Log ('[SKIP] ' + $item.Name + ' (manual)') }
        }
    }
}

function Restore-Defaults {
    Go-Home $Package
    Ensure-HeadsetSettings | Out-Null
    Set-SwitchState $true | Out-Null
    Set-ClickWindow 400 | Out-Null
    Set-Action '雙擊動作' '下一首' | Out-Null
    Set-Action '三擊動作' '上一首' | Out-Null
    Set-Action '長按動作' '關閉' | Out-Null
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
Assert-Device
$script:W, $script:H = Get-ScreenSize
Write-Log 'Metrolist Kilo release acceptance checks'
Write-Log "Device: $((Invoke-Adb shell getprop ro.product.model) -join '')  Screen: $($script:W)x$($script:H)"
Write-Log "Package: $Package"
Write-Log "Result file: $ResultFile"
Write-Log ''

$resolvedApk = $Apk
if (-not $resolvedApk) {
    $candidate = Join-Path $RepoRoot 'app\build\outputs\apk\foss\release\app-foss-arm64-v8a-release.apk'
    if (Test-Path -LiteralPath $candidate) { $resolvedApk = $candidate }
}
if ($resolvedApk) {
    Write-Log "APK: $resolvedApk"
    Test-ReleaseGates $resolvedApk

    if (-not $SkipInstall) {
        Write-Log '--- Install / launch release APK ---'
        $install = (Invoke-Adb install -r $resolvedApk) -join "`n"
        Add-TestResult 'Release APK installs' ($install -match 'Success') $install.Trim()
        if ($install -match 'Success') {
            Open-App $Package
            Start-Sleep -Seconds 5
            if (Ensure-HeadsetSettings) {
                $texts = Get-UiTexts (Get-UiXml)
                Add-TestResult 'Headset settings page is present' ($texts -contains '啟用多擊控制')
                $shot = Join-Path $ResultDir 'release-headset-settings.png'
                $remoteShot = '/sdcard/kilo_release_settings.png'
                Invoke-Adb shell screencap -p $remoteShot | Out-Null
                Invoke-Adb pull $remoteShot $shot | Out-Null
                Invoke-Adb shell rm $remoteShot | Out-Null
                Write-Log "Screenshot: $shot"
            } else {
                Add-TestResult 'Headset settings page is present' $false 'navigation failed'
            }
        }
    } else {
        Write-Log 'Install skipped (-SkipInstall).'
    }
} else {
    Add-Warn 'No release APK found; release gates and install were skipped.'
}

$pm = (Invoke-Adb shell pm path $Package) -join ''
if ($pm -notmatch 'package:') {
    throw "Package $Package is not installed. Build/install it first."
}

try {
    Write-Log ''
    Write-Log '--- Click-window boundaries (~350 ms gap) ---'
    Go-Home $Package
    Ensure-HeadsetSettings | Out-Null
    Ensure-Paused

    if (Set-ClickWindow 250) {
        Start-Sleep -Seconds 2
        Ensure-Paused
        $before = (Get-Playback).Title
        Send-TwoClicks 0.35
        $after = (Get-Playback).Title
        Add-TestResult '250 ms window splits a ~350 ms double click' ($before -eq $after) "before=$before after=$after"
    }

    Ensure-Paused
    if (Set-ClickWindow 700) {
        Start-Sleep -Seconds 2
        Ensure-Paused
        $before = (Get-Playback).Title
        Send-TwoClicks 0.35
        $after = (Get-Playback).Title
        Add-TestResult '700 ms window combines a ~350 ms double click' ($before -ne $after) "before=$before after=$after"
    }

    Write-Log ''
    Write-Log '--- Multi-click ON vs OFF response ---'
    if (Set-ClickWindow 700) {
        $onDelta = Measure-AverageDelta
        if ($onDelta -ne $null) { Write-Log "ON (700 ms) single-click delta: $onDelta ms" }
    }
    if (Set-SwitchState $false) {
        $offDelta = Measure-AverageDelta
        if ($offDelta -ne $null) { Write-Log "OFF single-click delta: $offDelta ms" }
        if ($onDelta -ne $null -and $offDelta -ne $null) {
            Add-TestResult 'OFF removes the click-window delay' (($onDelta - $offDelta) -ge 150) "on=$onDelta off=$offDelta"
        } else {
            Add-TestResult 'OFF removes the click-window delay' $false 'timing unavailable'
        }
    }
    Set-SwitchState $true | Out-Null

    Write-Log ''
    Write-Log '--- Restore defaults and verify persistence ---'
    Set-ClickWindow 400 | Out-Null
    Set-Action '雙擊動作' '下一首' | Out-Null
    Set-Action '三擊動作' '上一首' | Out-Null
    Set-Action '長按動作' '關閉' | Out-Null
    Start-Sleep -Seconds 2

    Invoke-Adb shell am force-stop $Package | Out-Null
    Start-Sleep -Seconds 1
    Open-App $Package
    Start-Sleep -Seconds 4
    Ensure-HeadsetSettings | Out-Null

    $seen = @()
    for ($i = 0; $i -lt 8; $i++) {
        $seen += Get-UiTexts (Get-UiXml)
        if (($seen -contains '400 毫秒') -and ($seen -contains '下一首') -and
            ($seen -contains '上一首') -and ($seen -contains '關閉')) { break }
        Swipe-Up
    }
    $has400 = $seen -contains '400 毫秒'
    $hasNext = $seen -contains '下一首'
    $hasPrevious = $seen -contains '上一首'
    $hasOff = $seen -contains '關閉'
    Add-TestResult 'Settings persist after app restart' ($has400 -and $hasNext -and $hasPrevious -and $hasOff) "400=$has400 next=$hasNext previous=$hasPrevious off=$hasOff"

    if (-not $SkipIdle) {
        Write-Log ''
        Write-Log '--- Stage 1 idle regression ---'
        Go-Home $Package
        Start-Sleep -Seconds 20

        $found = $false
        for ($i = 0; $i -lt 10; $i++) {
            $texts = Get-UiTexts (Get-UiXml)
            if ($texts -contains '快速存取') { $found = $true; break }
            Swipe-Up
        }
        if (-not $found) {
            for ($i = 0; $i -lt 10; $i++) {
                $texts = Get-UiTexts (Get-UiXml)
                if ($texts -contains '快速存取') { $found = $true; break }
                Swipe-Down
            }
        }
        if (-not $found) {
            Add-Warn '快速存取 was not found; measuring the current home position.'
        }
        $appPid = ((Invoke-Adb shell pidof $Package) -join ' ').Trim()
        if (-not $appPid) {
            Open-App $Package
            Start-Sleep -Seconds 5
        }
        Start-Sleep -Seconds 3

        $m = Measure-Idle $Package 10
        if ($m -and $m.Frames -lt 0) {
            Start-Sleep -Seconds 3
            $m = Measure-Idle $Package 10
        }
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
} finally {
    Write-Log ''
    Write-Log '--- Restore settings ---'
    try {
        Restore-Defaults
        Ensure-Paused
    } catch {
        Add-Warn ('Could not restore settings: ' + $_.Exception.Message)
    }
}

if ($Reboot) {
    Write-Log ''
    Write-Log '--- Reboot persistence ---'
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
        Add-TestResult 'Package survives reboot' ($pkgPath -match 'package:') $pkgPath.Trim()
        if (Ensure-HeadsetSettings) {
            $texts = Get-UiTexts (Get-UiXml)
            $ok = ($texts -contains '400 毫秒') -or ($texts -contains '點擊判定時間')
            Add-TestResult 'Headset settings survive reboot' $ok
        } else {
            Add-TestResult 'Headset settings survive reboot' $false 'navigation failed'
        }
    }
}

Invoke-ManualHeadsetChecklist

Write-Log ''
$failed = @($script:Results | Where-Object { -not $_.Ok })
$passed = @($script:Results | Where-Object { $_.Ok })
Write-Log ("SUMMARY: {0} passed, {1} failed" -f $passed.Count, $failed.Count)
Write-Log "Result file: $ResultFile"

if ($failed.Count -gt 0) { exit 1 }
exit 0
