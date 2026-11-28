# UTF-8 BOM is retained for Windows PowerShell 5.1.
$ErrorActionPreference = 'Stop'
$script:RawArgs = @($args)
$script:IsGuiLaunch = ($script:RawArgs -contains '--gui' -or $script:RawArgs -contains '--nogui')
$script:LogFile = $null
$script:LastCdpError = ''
$script:GuiFailureHandled = $false
$Lang = 'zh-CN'
$meta = $null
$PluginName = 'antigravity-zh-prompt'
$TagInfo = '[INFO]'
$TagOk   = '[OK]'
$TagWarn = '[WARN]'
$TagErr  = '[ERROR]'

function Resolve-ZhText {
    param([string]$Text)
    $value = [regex]::Unescape($Text)
    if ($Lang -and $Lang -ne 'zh-CN' -and $null -ne $meta) {
        $value = $value.Replace('Antigravity 中文', $meta.appName).Replace('antigravity-zh-prompt', $PluginName).Replace('中文', $meta.name)
    }
    return $value
}

function Write-AgyLog {
    param(
        [string]$Level = 'INFO',
        [string]$Message
    )
    if ([string]::IsNullOrWhiteSpace($script:LogFile) -or [string]::IsNullOrWhiteSpace($Message)) { return }
    try {
        $dir = Split-Path -Parent $script:LogFile
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        $ts = [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')
        [System.IO.File]::AppendAllText($script:LogFile, "[$ts] [$Level] $Message`r`n", [System.Text.UTF8Encoding]::new($false))
    } catch {}
}

function Reset-AgyLog {
    if ([string]::IsNullOrWhiteSpace($script:LogFile)) { return }
    try {
        $dir = Split-Path -Parent $script:LogFile
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        if ((Test-Path $script:LogFile) -and ((Get-Item $script:LogFile).Length -gt 262144)) {
            Move-Item -Force -Path $script:LogFile -Destination ($script:LogFile + '.1') -ErrorAction SilentlyContinue
        }
        $ts = [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss')
        [System.IO.File]::AppendAllText($script:LogFile, "`r`n===== Session $ts (PID $PID) =====`r`n", [System.Text.UTF8Encoding]::new($false))
    } catch {}
}

function Format-WinArg {
    param([string]$Value)
    if ($null -eq $Value) { return '""' }
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
    $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
    return '"' + $escaped + '"'
}

function Write-LaunchState {
    param(
        [string]$StateFile,
        [string]$Code,
        [string]$Message = ''
    )
    if ([string]::IsNullOrWhiteSpace($StateFile)) { return }
    $clean = if ($null -eq $Message) { '' } else { ($Message -replace '[\r\n]+', ' ').Trim() }
    $line = "$Code|$clean`n"
    for ($attempt = 0; $attempt -lt 3; $attempt++) {
        try {
            [System.IO.File]::AppendAllText($StateFile, $line, [System.Text.UTF8Encoding]::new($false))
            return
        } catch {
            Start-Sleep -Milliseconds 20
        }
    }
}

function Read-LaunchStateLines {
    param([string]$StateFile)
    if ([string]::IsNullOrWhiteSpace($StateFile) -or -not (Test-Path $StateFile)) { return @() }
    try {
        $fs = [System.IO.File]::Open($StateFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $sr = [System.IO.StreamReader]::new($fs, [System.Text.Encoding]::UTF8)
            try {
                $content = $sr.ReadToEnd()
            } finally {
                $sr.Dispose()
            }
        } finally {
            $fs.Dispose()
        }
        if ([string]::IsNullOrEmpty($content)) { return @() }
        return @($content -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    } catch {
        return @()
    }
}

function Pause-GuiConsole {
    param(
        [string]$FallbackTitle = 'Antigravity',
        [string]$FallbackMessage = ''
    )
    $promptText = Resolve-ZhText '\u6309\u56de\u8f66\u952e\u5173\u95ed\u6b64\u7a97\u53e3...'
    try {
        if (-not [Console]::IsInputRedirected) {
            Write-Host ''
            $null = Read-Host -Prompt $promptText
            return
        }
    } catch {}
    if (-not [string]::IsNullOrWhiteSpace($FallbackMessage)) {
        try {
            $null = (New-Object -ComObject WScript.Shell).Popup($FallbackMessage, 0, $FallbackTitle, 0x1010)
        } catch {}
    }
}

$InstallRoot = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } elseif ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'antigravity-zh-launcher' } else { '.' }
$LogsDir     = Join-Path $InstallRoot 'logs'
$script:LogFile = Join-Path $LogsDir 'agy-zh.log'

try {
$AssetRoot = if (Test-Path (Join-Path $PSScriptRoot '..\locales\index.json')) {
    Split-Path -Parent $PSScriptRoot
} else { Join-Path $PSScriptRoot 'agy-i18n' }
. (Join-Path $AssetRoot 'lib\options.ps1')
$options = Read-AgyOptions -Arguments $script:RawArgs -Runtime
$Lang = $options.Lang
$SubCommand = if ($options.Help) { 'help' } elseif ($options.Rest.Count) { $options.Rest[0] } else { 'start' }
$RestArgs = @($options.Rest | Select-Object -Skip 1)
$index = Get-Content -Raw -Encoding UTF8 (Join-Path $AssetRoot 'locales\index.json') | ConvertFrom-Json
$meta = $index.$Lang
. (Join-Path $AssetRoot 'lib\locale.ps1')
. (Join-Path $AssetRoot 'lib\zh-overlay.ps1')
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch {}
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Net.Http

$PluginName     = $meta.pluginName
$TagInfo = Resolve-ZhText '[\u4fe1\u606f]'
$TagOk   = Resolve-ZhText '[\u6210\u529f]'
$TagWarn = Resolve-ZhText '[\u63d0\u793a]'
$TagErr  = Resolve-ZhText '[\u9519\u8bef]'
$OverlayVersion = 'agy-zh-v8'
$ShortcutName   = $meta.appName + '.lnk'
$OverlayUrl     = if ($env:AGY_ZH_OVERLAY_URL) { $env:AGY_ZH_OVERLAY_URL } else { 'https://raw.githubusercontent.com/yuexps/Antigravity-Hans/main/resources/antigravity-hans-overlay.js' }
$ConfigDir      = if ($env:GEMINI_CONFIG_DIR) { $env:GEMINI_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.gemini\config' }
$ConfigFile     = Join-Path $ConfigDir 'config.json'
$PluginDir      = Join-Path $ConfigDir "plugins\$PluginName"
$WatcherPidFile = Join-Path $LogsDir $(if ($Lang -eq 'zh-CN') { 'watcher.pid' } else { $meta.command + '.pid' })
$LogFile        = Join-Path $LogsDir $(if ($Lang -eq 'zh-CN') { 'agy-zh.log' } else { $meta.command + '.log' })
$script:LogFile = $LogFile
$BaseOverlayJs  = Join-Path $PSScriptRoot 'antigravity-hans-overlay.base.js'
$OverlayJs      = Join-Path $PSScriptRoot $(if ($Lang -eq 'zh-CN') { 'antigravity-hans-overlay.js' } else { 'antigravity-' + $Lang + '-overlay.js' })

$script:CdpHttpHandler = [System.Net.Http.HttpClientHandler]::new()
$script:CdpHttpHandler.UseProxy = $false
$script:CdpHttpClient = [System.Net.Http.HttpClient]::new($script:CdpHttpHandler)
$script:CdpHttpClient.Timeout = [TimeSpan]::FromMilliseconds(1500)
$script:CdpCmdId = 1

function Set-ZhPluginEnabled {
    param([bool]$Enabled)
    New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
    $data = [PSCustomObject]@{}
    if (Test-Path $ConfigFile) {
        $raw = Get-Content -Raw -Encoding UTF8 -Path $ConfigFile
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $parsed = $raw | ConvertFrom-Json
            if ($null -ne $parsed) { $data = $parsed }
        }
    }
    if (-not ($data.PSObject.Properties.Name -contains 'plugins') -or $null -eq $data.plugins) {
        $data | Add-Member -NotePropertyName 'plugins' -NotePropertyValue ([PSCustomObject]@{}) -Force
    }
    if ($Enabled) {
        foreach ($item in $index.PSObject.Properties) {
            $other = $item.Value.pluginName
            if ($other -ne $PluginName -and $data.plugins.PSObject.Properties.Name -contains $other) {
                $data.plugins.$other | Add-Member -NotePropertyName enabled -NotePropertyValue $false -Force
            }
        }
    }
    $entry = $null
    if ($data.plugins.PSObject.Properties.Name -contains $PluginName) {
        $entry = $data.plugins.$PluginName
    }
    if ($null -eq $entry) {
        $entry = [PSCustomObject]@{}
        $data.plugins | Add-Member -NotePropertyName $PluginName -NotePropertyValue $entry -Force
    }
    $entry | Add-Member -NotePropertyName 'enabled' -NotePropertyValue $Enabled -Force

    $json = ($data | ConvertTo-Json -Depth 20) + "`n"
    $tmpPath = Join-Path $ConfigDir ('.config.' + [System.Guid]::NewGuid().ToString('N') + '.tmp')
    [System.IO.File]::WriteAllText($tmpPath, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -Force $tmpPath $ConfigFile
}

function Get-ZhPluginEnabled {
    if (Test-Path $ConfigFile) {
        try {
            $data = Get-Content -Raw -Encoding UTF8 -Path $ConfigFile | ConvertFrom-Json
            if ($null -ne $data.plugins -and ($data.plugins.PSObject.Properties.Name -contains $PluginName)) {
                $val = $data.plugins.$PluginName.enabled
                if ($val -is [bool]) { return $val }
            }
        } catch {}
    }
    $pluginJson = Join-Path $PluginDir 'plugin.json'
    if (Test-Path $pluginJson) {
        try {
            $pdata = Get-Content -Raw -Encoding UTF8 -Path $pluginJson | ConvertFrom-Json
            if ($pdata.disabled -eq $true) { return $false }
            return $true
        } catch {}
    }
    return $false
}

function Get-ActiveWatcherPids {
    if (-not (Test-Path $WatcherPidFile)) { return @() }
    try {
        $watcherId = [int](Get-Content -Raw $WatcherPidFile).Trim()
        if ($watcherId -eq $PID) { return @() }
        $p = Get-CimInstance Win32_Process -Filter "ProcessId = $watcherId" -ErrorAction SilentlyContinue
        if ($p -and $p.CommandLine -match 'agy-zh\.ps1') { return @($watcherId) }
    } catch {}
    return @()
}

function Stop-PreviousLanguageWatchers {
    foreach ($item in $index.PSObject.Properties) {
        $pidPath = Join-Path $LogsDir $(if ($item.Name -eq 'zh-CN') { 'watcher.pid' } else { $item.Value.command + '.pid' })
        if (Test-Path $pidPath) {
            try {
                $watcherId = [int](Get-Content -Raw $pidPath).Trim()
                $p = Get-CimInstance Win32_Process -Filter "ProcessId = $watcherId" -ErrorAction SilentlyContinue
                if ($watcherId -ne $PID -and $p -and $p.CommandLine -match 'agy-zh\.ps1') {
                    Stop-Process -Id $watcherId -Force -ErrorAction Stop
                    Wait-Process -Id $watcherId -Timeout 10 -ErrorAction SilentlyContinue
                }
            } catch { throw "Could not stop previous language session: $_" }
        }
    }
}

function Test-ActiveWatcher {
    return (@(Get-ActiveWatcherPids).Count -gt 0)
}

function Find-OriginalExe {
    $candidates = @()
    if ($env:LOCALAPPDATA) { $candidates += (Join-Path $env:LOCALAPPDATA 'Programs\Antigravity\Antigravity.exe') }
    if (${env:ProgramFiles}) {
        $candidates += (Join-Path ${env:ProgramFiles} 'Antigravity\Antigravity.exe')
        $candidates += (Join-Path ${env:ProgramFiles} 'Google Antigravity\Antigravity.exe')
    }
    if (${env:ProgramFiles(x86)}) { $candidates += (Join-Path ${env:ProgramFiles(x86)} 'Antigravity\Antigravity.exe') }
    foreach ($p in $candidates) {
        if ($p -and (Test-Path $p)) { return $p }
    }

    try {
        $wsh = New-Object -ComObject WScript.Shell
        foreach ($dir in @(([Environment]::GetFolderPath('Desktop')), ([Environment]::GetFolderPath('Programs')))) {
            if ([string]::IsNullOrWhiteSpace($dir)) { continue }
            $lnk = Join-Path $dir 'Antigravity.lnk'
            if (Test-Path $lnk) {
                $target = $wsh.CreateShortcut($lnk).TargetPath
                if ($target -and $target.EndsWith('\Antigravity.exe', [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path $target)) {
                    return $target
                }
            }
        }
    } catch {}

    foreach ($regPath in @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )) {
        try {
            $items = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like '*Antigravity*' }
            foreach ($item in $items) {
                if (-not [string]::IsNullOrWhiteSpace($item.InstallLocation)) {
                    $exeFromLoc = Join-Path $item.InstallLocation.Trim().Trim('"') 'Antigravity.exe'
                    if (Test-Path $exeFromLoc) { return $exeFromLoc }
                }
                if (-not [string]::IsNullOrWhiteSpace($item.DisplayIcon)) {
                    $exeFromIcon = ($item.DisplayIcon.Trim() -replace ',\s*-?\d+$', '').Trim().Trim('"')
                    if ($exeFromIcon -and $exeFromIcon.EndsWith('\Antigravity.exe', [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path $exeFromIcon)) {
                        return $exeFromIcon
                    }
                }
            }
        } catch {}
    }

    return $null
}

function Start-AntigravityProcess {
    param(
        [string]$ExePath,
        [string[]]$Arguments = @()
    )
    if ([string]::IsNullOrWhiteSpace($ExePath)) { return $null }
    $workDir = Split-Path -Parent $ExePath
    $hasArgs = ($null -ne $Arguments -and $Arguments.Count -gt 0)
    try {
        New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null
        Get-ChildItem -Path $LogsDir -Filter 'antigravity-app-*.log' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTimeUtc -lt [DateTime]::UtcNow.AddDays(-1) } |
            Remove-Item -Force -ErrorAction SilentlyContinue
        $stamp = [System.Guid]::NewGuid().ToString('N').Substring(0, 8)
        $outLog = Join-Path $LogsDir "antigravity-app-$stamp.out.log"
        $errLog = Join-Path $LogsDir "antigravity-app-$stamp.err.log"
        $spParams = @{
            FilePath               = $ExePath
            WorkingDirectory       = $workDir
            RedirectStandardOutput = $outLog
            RedirectStandardError  = $errLog
            PassThru               = $true
        }
        if ($hasArgs) {
            $spParams['ArgumentList'] = $Arguments
        }
        $proc = Start-Process @spParams
        if ($null -ne $proc) { return $proc }
    } catch {
        Write-AgyLog -Level 'WARN' -Message "Redirected Antigravity launch failed ($($_.Exception.Message)); falling back to plain Start-Process."
    }
    $fallbackParams = @{
        FilePath         = $ExePath
        WorkingDirectory = $workDir
        PassThru         = $true
    }
    if ($hasArgs) {
        $fallbackParams['ArgumentList'] = $Arguments
    }
    return (Start-Process @fallbackParams)
}

function Get-SameSessionAntigravityPids {
    $mySession = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
    $pids = [int[]]@(
        Get-Process -Name 'Antigravity' -ErrorAction SilentlyContinue |
            Where-Object { $_.SessionId -eq $mySession } |
            ForEach-Object { [int]$_.Id }
    )
    return $pids
}

function Ensure-AgyWin32Type {
    if ('AgyWin32' -as [type]) { return $true }
    $win32Code = @(
        'using System;',
        'using System.Runtime.InteropServices;',
        'public static class AgyWin32 {',
        '    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);',
        '    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);',
        '    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);',
        '    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);',
        '    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);',
        '    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);',
        '    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);',
        '    public static bool HasVisibleWindow(int[] targetPids) {',
        '        if (targetPids == null || targetPids.Length == 0) return false;',
        '        bool found = false;',
        '        EnumWindows(delegate(IntPtr hWnd, IntPtr lParam) {',
        '            if (!IsWindowVisible(hWnd)) return true;',
        '            uint pid = 0;',
        '            if (GetWindowThreadProcessId(hWnd, out pid) != 0 && Array.IndexOf(targetPids, (int)pid) >= 0) {',
        '                found = true;',
        '                return false;',
        '            }',
        '            return true;',
        '        }, IntPtr.Zero);',
        '        return found;',
        '    }',
        '    public static bool FocusFirstVisibleWindow(int[] targetPids) {',
        '        if (targetPids == null || targetPids.Length == 0) return false;',
        '        IntPtr targetHwnd = IntPtr.Zero;',
        '        EnumWindows(delegate(IntPtr hWnd, IntPtr lParam) {',
        '            if (!IsWindowVisible(hWnd)) return true;',
        '            uint pid = 0;',
        '            if (GetWindowThreadProcessId(hWnd, out pid) != 0 && Array.IndexOf(targetPids, (int)pid) >= 0) {',
        '                targetHwnd = hWnd;',
        '                return false;',
        '            }',
        '            return true;',
        '        }, IntPtr.Zero);',
        '        if (targetHwnd == IntPtr.Zero) return false;',
        '        if (IsIconic(targetHwnd)) ShowWindow(targetHwnd, 9);',
        '        SetForegroundWindow(targetHwnd);',
        '        return true;',
        '    }',
        '}'
    ) -join "`n"
    try { Add-Type -TypeDefinition $win32Code -ErrorAction Stop } catch {}
    return ($null -ne ('AgyWin32' -as [type]))
}

function Test-VisibleWindowForPids {
    param([int[]]$TargetPids)
    if ($null -eq $TargetPids -or $TargetPids.Count -eq 0) { return $false }
    if (Ensure-AgyWin32Type) {
        return [AgyWin32]::HasVisibleWindow($TargetPids)
    }
    return (@(Get-Process -Id $TargetPids -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero }).Count -gt 0)
}

function Focus-VisibleWindowForPids {
    param([int[]]$TargetPids)
    if ($null -eq $TargetPids -or $TargetPids.Count -eq 0) { return $false }
    if (Ensure-AgyWin32Type) {
        try { return [AgyWin32]::FocusFirstVisibleWindow($TargetPids) } catch { return $false }
    }
    return $false
}

function Invoke-LocalCdpJson {
    param(
        [int]$Port,
        [string]$Path
    )
    if ($Port -le 0 -or $Port -gt 65535) { return $null }
    try {
        $json = $script:CdpHttpClient.GetStringAsync("http://127.0.0.1:$Port$Path").GetAwaiter().GetResult()
        if ([string]::IsNullOrWhiteSpace($json)) {
            $script:LastCdpError = "Empty HTTP response from 127.0.0.1:$Port$Path"
            return $null
        }
        $script:LastCdpError = ''
        return ($json | ConvertFrom-Json)
    } catch {
        $ex = $_.Exception
        while ($null -ne $ex.InnerException) { $ex = $ex.InnerException }
        $script:LastCdpError = $ex.Message
        return $null
    }
}

function Get-DebugAntigravityPort {
    $pids = @(Get-SameSessionAntigravityPids)
    if ($pids.Count -eq 0) { return 0 }
    $cimProcs = @(Get-CimInstance Win32_Process -Filter "Name = 'Antigravity.exe'" -ErrorAction SilentlyContinue)
    foreach ($p in $cimProcs) {
        if ($pids -contains [int]$p.ProcessId -and $p.CommandLine -match '--remote-debugging-port=(\d+)') {
            $port = [int]$Matches[1]
            $ver = Invoke-LocalCdpJson -Port $port -Path '/json/version'
            if ($null -ne $ver) {
                return $port
            }
        }
    }
    return 0
}

function Stop-AntigravityProcessesByIds {
    param([int[]]$TargetPids)
    if ($null -eq $TargetPids -or $TargetPids.Count -eq 0) { return }
    Stop-Process -Id $TargetPids -Force -ErrorAction SilentlyContinue
    foreach ($id in $TargetPids) {
        if (Get-Process -Id $id -ErrorAction SilentlyContinue) {
            try { & taskkill.exe /F /PID $id 2>$null | Out-Null } catch {}
        }
    }
    for ($i = 0; $i -lt 25; $i++) {
        if (@(Get-SameSessionAntigravityPids).Count -eq 0) { break }
        Start-Sleep -Milliseconds 200
    }
    Start-Sleep -Milliseconds 500
}

function Prepare-AntigravityForZhLaunch {
    param([bool]$GuiMode = $false)
    if ((Get-DebugAntigravityPort) -gt 0) {
        return $true
    }
    $pids = @(Get-SameSessionAntigravityPids)
    if ($pids.Count -eq 0) { return $true }

    $hasVisible = Test-VisibleWindowForPids -TargetPids $pids
    if (-not $hasVisible) {
        $pidText = ($pids -join ', ')
        Write-AgyLog -Level 'INFO' -Message "Cleaning headless Antigravity PIDs: $pidText"
        Write-Host "$TagWarn $(Resolve-ZhText '\u68c0\u6d4b\u5230 Antigravity \u65e0\u754c\u9762\u540e\u53f0\u8fdb\u7a0b') (PID: $pidText)$(Resolve-ZhText '\uff0c\u6b63\u5728\u81ea\u52a8\u6e05\u7406...')"
        Stop-AntigravityProcessesByIds -TargetPids $pids
        $leftover = @(Get-SameSessionAntigravityPids)
        if ($leftover.Count -gt 0 -and (Get-DebugAntigravityPort) -eq 0) {
            throw "$(Resolve-ZhText '\u65e0\u6cd5\u81ea\u52a8\u6e05\u7406\u6b8b\u7559\u7684 Antigravity \u540e\u53f0\u8fdb\u7a0b') (PID: $($leftover -join ', '))$(Resolve-ZhText '\uff08\u53ef\u80fd\u4ee5\u7ba1\u7406\u5458\u6743\u9650\u8fd0\u884c\uff09\uff0c\u8bf7\u5148\u624b\u52a8\u7ed3\u675f\u540e\u91cd\u8bd5\u3002')"
        }
        return $true
    }

    if ($GuiMode) {
        Write-Host ''
        Write-Host "$TagWarn $(Resolve-ZhText '\u68c0\u6d4b\u5230\u539f\u7248 Antigravity \u7a97\u53e3\u6b63\u5728\u8fd0\u884c\uff08\u672a\u5f00\u542f\u4e2d\u6587\u8c03\u8bd5\u7aef\u53e3\uff09\u3002')" -ForegroundColor Yellow
        Write-Host (Resolve-ZhText '      \u9700\u8981\u5148\u4fdd\u5b58\u72b6\u6001\u5e76\u91cd\u542f\u4e3a\u300cAntigravity \u4e2d\u6587\u300d\u624d\u80fd\u6ce8\u5165\u6c49\u5316\u3002')
        $confirmed = $true
        $prompted = $false
        try {
            if (-not [Console]::IsInputRedirected) {
                $reply = Read-Host -Prompt (Resolve-ZhText '\u6309\u56de\u8f66\u7ee7\u7eed\u91cd\u542f\uff0c\u8f93\u5165 N \u53d6\u6d88')
                $prompted = $true
                if ($reply -and $reply.Trim().ToLowerInvariant() -in @('n', 'no')) {
                    $confirmed = $false
                }
            }
        } catch {}
        if (-not $prompted) {
            $wsh = New-Object -ComObject WScript.Shell
            $msg = Resolve-ZhText '\u68c0\u6d4b\u5230\u539f\u7248 Antigravity \u7a97\u53e3\u6b63\u5728\u8fd0\u884c\uff08\u672a\u5f00\u542f\u4e2d\u6587\u8c03\u8bd5\u7aef\u53e3\uff09\u3002\n\n\u662f\u5426\u4fdd\u5b58\u72b6\u6001\u5e76\u91cd\u542f\u4e3a\u300cAntigravity \u4e2d\u6587\u300d\uff1f'
            $title = Resolve-ZhText 'Antigravity \u4e2d\u6587'
            $ans = $wsh.Popup($msg, 0, $title, 0x1024)
            if ($ans -ne 6) { $confirmed = $false }
        }
        if (-not $confirmed) {
            Write-Host "$TagInfo $(Resolve-ZhText '\u5df2\u53d6\u6d88\u542f\u52a8\u3002')"
            Write-AgyLog -Level 'INFO' -Message 'User cancelled restart of running non-debug Antigravity.'
            return $false
        }
        Write-Host "$TagInfo $(Resolve-ZhText '\u6b63\u5728\u8bf7\u6c42\u5df2\u8fd0\u884c\u7684 Antigravity \u4fdd\u5b58\u72b6\u6001\u5e76\u9000\u51fa...')"
    } else {
        Write-Host "$TagWarn $(Resolve-ZhText '\u6b63\u5728\u8bf7\u6c42\u5df2\u8fd0\u884c\u7684 Antigravity \u4fdd\u5b58\u72b6\u6001\u5e76\u9000\u51fa...')"
    }

    Write-AgyLog -Level 'INFO' -Message "Closing running Antigravity PIDs: $($pids -join ', ')"
    foreach ($id in $pids) {
        try { & taskkill.exe /PID $id 2>$null | Out-Null } catch {}
    }
    for ($i = 0; $i -lt 25; $i++) {
        $cur = @(Get-SameSessionAntigravityPids)
        if ($cur.Count -eq 0) { return $true }
        if (-not (Test-VisibleWindowForPids -TargetPids $cur)) { break }
        Start-Sleep -Milliseconds 200
    }
    $rem = @(Get-SameSessionAntigravityPids)
    if ($rem.Count -gt 0 -and ($GuiMode -or -not (Test-VisibleWindowForPids -TargetPids $rem))) {
        Stop-AntigravityProcessesByIds -TargetPids $rem
    }
    $leftoverAfter = @(Get-SameSessionAntigravityPids)
    if ($leftoverAfter.Count -gt 0 -and (Get-DebugAntigravityPort) -eq 0) {
        throw "$(Resolve-ZhText '\u65e0\u6cd5\u81ea\u52a8\u9000\u51fa\u5df2\u8fd0\u884c\u7684 Antigravity \u8fdb\u7a0b') (PID: $($leftoverAfter -join ', '))$(Resolve-ZhText '\uff08\u53ef\u80fd\u4ee5\u7ba1\u7406\u5458\u6743\u9650\u8fd0\u884c\uff09\uff0c\u8bf7\u5148\u4fdd\u5b58\u5de5\u4f5c\u5e76\u624b\u52a8\u9000\u51fa\u540e\u91cd\u8bd5\u3002')"
    }
    return $true
}

function Get-FreeLoopbackPort {
    foreach ($p in 58321..58325) {
        $listener = $null
        try {
            $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $p)
            $listener.Start()
            return $p
        } catch {
        } finally {
            if ($null -ne $listener) {
                try { $listener.Stop() } catch {}
            }
        }
    }
    throw (Resolve-ZhText '\u5019\u9009\u8c03\u8bd5\u7aef\u53e3 (58321-58325) \u5747\u88ab\u5360\u7528\u3002')
}

function Test-ValidCdpWsUrl {
    param(
        [string]$WsUrl,
        [int]$ExpectedPort
    )
    if ([string]::IsNullOrWhiteSpace($WsUrl)) { return $false }
    try {
        $u = [Uri]$WsUrl
        if ($u.Scheme -ne 'ws') { return $false }
        $h = $u.DnsSafeHost.ToLowerInvariant()
        if ($h -ne '127.0.0.1' -and $h -ne 'localhost' -and $h -ne '::1') { return $false }
        if ($u.Port -ne $ExpectedPort) { return $false }
        return ($u.AbsolutePath.StartsWith('/devtools/page/') -or $u.AbsolutePath.StartsWith('/devtools/browser/'))
    } catch {
        return $false
    }
}

function Test-CdpTargetMatch {
    param([object]$Target)
    if ($null -eq $Target) { return $false }
    $tType = [string]$Target.type
    if ($tType -in @('worker', 'service_worker', 'shared_worker', 'background_page')) { return $false }
    $rawUrl = [string]$Target.url
    if ([string]::IsNullOrWhiteSpace($rawUrl)) { return $false }
    $lower = $rawUrl.ToLowerInvariant()
    if ($lower.StartsWith('data:text/html')) { return $true }
    try {
        $u = [Uri]$rawUrl
        if (($u.Scheme -eq 'http' -or $u.Scheme -eq 'https') -and [string]::IsNullOrEmpty($u.UserInfo)) {
            $h = $u.DnsSafeHost.ToLowerInvariant()
            if ($h -eq '127.0.0.1' -or $h -eq 'localhost' -or $h -eq '::1') { return $true }
        }
        if ($tType -eq 'iframe' -and $u.Scheme -eq 'plugin' -and [string]::IsNullOrEmpty($u.UserInfo) -and $u.IsDefaultPort -and ($u.AbsolutePath -eq '' -or $u.AbsolutePath -eq '/') -and [string]::IsNullOrEmpty($u.Query) -and [string]::IsNullOrEmpty($u.Fragment)) {
            if ($u.DnsSafeHost.ToLowerInvariant() -match '^swarm--swarm_board-[a-z0-9]{5}$') { return $true }
        }
    } catch {}
    return $false
}

function Connect-LocalWebSocket {
    param([string]$WsUrl)
    $ws = [System.Net.WebSockets.ClientWebSocket]::new()
    try { $ws.Options.Proxy = $null } catch {}
    $cts = [System.Threading.CancellationTokenSource]::new(5000)
    try {
        $null = $ws.ConnectAsync([Uri]$WsUrl, $cts.Token).GetAwaiter().GetResult()
        return $ws
    } catch {
        $ws.Dispose()
        throw
    } finally {
        $cts.Dispose()
    }
}

function Invoke-CdpWsCommand {
    param(
        [System.Net.WebSockets.ClientWebSocket]$Ws,
        [string]$Method,
        [object]$Params = @{}
    )
    $cmdId = $script:CdpCmdId
    $script:CdpCmdId++
    $payloadObj = @{
        id     = $cmdId
        method = $Method
        params = $Params
    }
    $jsonText = $payloadObj | ConvertTo-Json -Depth 10 -Compress
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($jsonText)
    $cts = [System.Threading.CancellationTokenSource]::new(15000)
    $recvBuf = New-Object byte[] 65536
    $recvSeg = [System.ArraySegment[byte]]::new($recvBuf)
    $ms = [System.IO.MemoryStream]::new()
    try {
        $chunkSize = 65536
        if ($bytes.Length -eq 0) {
            $emptySeg = [System.ArraySegment[byte]]::new($bytes)
            $null = $Ws.SendAsync($emptySeg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).GetAwaiter().GetResult()
        } else {
            $offset = 0
            while ($offset -lt $bytes.Length) {
                $count = [Math]::Min($chunkSize, $bytes.Length - $offset)
                $isEnd = (($offset + $count) -ge $bytes.Length)
                $sendSeg = [System.ArraySegment[byte]]::new($bytes, $offset, $count)
                $null = $Ws.SendAsync($sendSeg, [System.Net.WebSockets.WebSocketMessageType]::Text, $isEnd, $cts.Token).GetAwaiter().GetResult()
                $offset += $count
            }
        }
        while ($true) {
            $ms.SetLength(0)
            do {
                $res = $Ws.ReceiveAsync($recvSeg, $cts.Token).GetAwaiter().GetResult()
                if ($res.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                    throw 'WebSocket closed'
                }
                if ($res.Count -gt 0) {
                    $ms.Write($recvBuf, 0, $res.Count)
                }
            } while (-not $res.EndOfMessage)

            $msgText = [System.Text.Encoding]::UTF8.GetString($ms.GetBuffer(), 0, [int]$ms.Length)
            $msg = $msgText | ConvertFrom-Json
            if ($null -ne $msg -and ($msg.PSObject.Properties.Name -contains 'id') -and [int]$msg.id -eq $cmdId) {
                if ($msg.PSObject.Properties.Name -contains 'error' -and $null -ne $msg.error) {
                    throw "CDP $Method error: $($msg.error.message)"
                }
                if ($null -ne $msg.result -and ($msg.result.PSObject.Properties.Name -contains 'exceptionDetails') -and $null -ne $msg.result.exceptionDetails) {
                    throw "Runtime.evaluate exception: $($msg.result.exceptionDetails.text)"
                }
                return $msg.result
            }
        }
    } finally {
        $ms.Dispose()
        $cts.Dispose()
    }
}

function Invoke-InjectTarget {
    param(
        [object]$Target,
        [int]$Port,
        [string]$OverlaySource,
        [string]$Fingerprint
    )
    if (-not (Test-CdpTargetMatch -Target $Target)) { return 'none' }
    $tid = [string]$Target.id
    if ([string]::IsNullOrWhiteSpace($tid)) { return 'none' }
    $wsUrl = if ($Target.webSocketDebuggerUrl) { [string]$Target.webSocketDebuggerUrl } else { "ws://127.0.0.1:$Port/devtools/page/$tid" }
    if (-not (Test-ValidCdpWsUrl -WsUrl $wsUrl -ExpectedPort $Port)) { return 'none' }

    $u = $null
    try { $u = [Uri]([string]$Target.url) } catch {}
    $isSwarm = ($null -ne $u -and ([string]$Target.type) -eq 'iframe' -and $u.Scheme -eq 'plugin')

    $ws = $null
    try {
        $ws = Connect-LocalWebSocket -WsUrl $wsUrl
        $fpJson = $Fingerprint | ConvertTo-Json -Compress
        $checkExpr = "window.__antigravityZhPatchInstalled === true && window.__observedDocument === document && window.__antigravityZhPatchFingerprint === $fpJson"

        $chk = Invoke-CdpWsCommand -Ws $ws -Method 'Runtime.evaluate' -Params @{ expression = $checkExpr; returnByValue = $true }
        if ($null -ne $chk -and $null -ne $chk.result -and $chk.result.value -eq $true) {
            return 'already'
        }

        $wrapped = "window.__antigravityZhPatchRequestedFingerprint = $fpJson;`n$OverlaySource"
        if ($isSwarm) {
            $hostJson = $u.Host | ConvertTo-Json -Compress
            $wrapped = "(() => { if (location.protocol !== 'plugin:' || location.hostname !== $hostJson || (location.pathname !== '/' && location.pathname !== '') || !document.querySelector('[data-testid=`"swarm-tabs`"]') || !document.querySelector('[data-testid=`"swarm-empty-state`"]')) return;`n$wrapped`n})()"
        } else {
            try { $null = Invoke-CdpWsCommand -Ws $ws -Method 'Page.enable' -Params @{} } catch {}
            $null = Invoke-CdpWsCommand -Ws $ws -Method 'Page.addScriptToEvaluateOnNewDocument' -Params @{ source = $wrapped }
        }

        $null = Invoke-CdpWsCommand -Ws $ws -Method 'Runtime.evaluate' -Params @{ expression = $wrapped; awaitPromise = $false }
        $verify = Invoke-CdpWsCommand -Ws $ws -Method 'Runtime.evaluate' -Params @{ expression = $checkExpr; returnByValue = $true }
        if ($null -ne $verify -and $null -ne $verify.result -and $verify.result.value -eq $true) {
            return 'injected'
        }
        return 'none'
    } finally {
        if ($null -ne $ws) {
            try { $ws.Dispose() } catch {}
        }
    }
}

function Start-CdpWatchLoop {
    param(
        [bool]$GuiMode = $false,
        [int]$FixedPort = 0,
        [bool]$LaunchApp = $false,
        [string]$StateFile = '',
        [bool]$QuietConsole = $false
    )
    $writeStep = {
        param([string]$Level, [string]$Tag, [string]$Text, [string]$Color = '')
        Write-AgyLog -Level $Level -Message $Text
        if (-not $QuietConsole) {
            $line = if ($Tag) { "$Tag $Text" } else { $Text }
            if ($Color) { Write-Host $line -ForegroundColor $Color } else { Write-Host $line }
        }
    }

    $overlaySource = [System.IO.File]::ReadAllText($OverlayJs, [System.Text.Encoding]::UTF8)
    $fingerprint = (Get-FileHash -Algorithm SHA256 -Path $OverlayJs).Hash.ToLowerInvariant().Substring(0, 16)

    $port = if ($FixedPort -gt 0 -and -not $LaunchApp) {
        $FixedPort
    } elseif ($FixedPort -gt 0 -and $LaunchApp) {
        0
    } else {
        Get-DebugAntigravityPort
    }

    $origExe = Find-OriginalExe
    if ($port -gt 0) {
        $ver = Invoke-LocalCdpJson -Port $port -Path '/json/version'
        if ($null -eq $ver) {
            $errDetail = if ($script:LastCdpError) { " ($($script:LastCdpError))" } else { '' }
            $msg = "$(Resolve-ZhText '\u65e0\u6cd5\u8fde\u63a5 Antigravity \u8c03\u8bd5\u7aef\u53e3') ($port)$errDetail"
            Write-LaunchState -StateFile $StateFile -Code 'ERROR' -Message $msg
            Write-AgyLog -Level 'ERROR' -Message $msg
            throw $msg
        }
        & $writeStep 'INFO' $TagInfo "$(Resolve-ZhText '\u68c0\u6d4b\u5230 Antigravity \u5df2\u4ee5\u4e2d\u6587\u8c03\u8bd5\u6a21\u5f0f\u8fd0\u884c (\u7aef\u53e3') $port$(Resolve-ZhText ')\uff0c\u76f4\u63a5\u9644\u7740\u76d1\u89c6\u3002')" ''
        if ($FixedPort -le 0 -and ($GuiMode -or -not [string]::IsNullOrWhiteSpace($StateFile))) {
            $focused = Focus-VisibleWindowForPids -TargetPids @(Get-SameSessionAntigravityPids)
            if (-not $focused -and $origExe) {
                Write-AgyLog -Level 'INFO' -Message 'Debug port active with no visible window; opening Antigravity window.'
                $null = Start-AntigravityProcess -ExePath $origExe
            }
        }
    } else {
        if (-not $origExe) {
            $msg = Resolve-ZhText '\u672a\u627e\u5230 Antigravity.exe \u5b89\u88c5\u8def\u5f84\u3002'
            Write-LaunchState -StateFile $StateFile -Code 'ERROR' -Message $msg
            Write-AgyLog -Level 'ERROR' -Message $msg
            throw $msg
        }
        $port = if ($FixedPort -gt 0) { $FixedPort } else { Get-FreeLoopbackPort }
        & $writeStep 'INFO' $TagInfo "$(Resolve-ZhText '[3/4] \u6b63\u5728\u542f\u52a8 Antigravity \u4e2d\u6587\u8c03\u8bd5\u4f1a\u8bdd (\u7aef\u53e3') $port)..." ''
        $null = Start-AntigravityProcess -ExePath $origExe -Arguments @("--remote-debugging-port=$port", '--remote-debugging-address=127.0.0.1')
        Write-LaunchState -StateFile $StateFile -Code 'PHASE' -Message "APP_LAUNCHED|$port"
        $ready = $false
        $launchStart = [DateTime]::UtcNow
        $deadline = $launchStart.AddSeconds(35)
        $lastReportSec = 0
        while ([DateTime]::UtcNow -lt $deadline) {
            if ($null -ne (Invoke-LocalCdpJson -Port $port -Path '/json/version')) {
                $ready = $true
                break
            }
            $elapsedSec = [int]([DateTime]::UtcNow - $launchStart).TotalSeconds
            if ($elapsedSec -ge ($lastReportSec + 3)) {
                $lastReportSec = $elapsedSec
                Write-LaunchState -StateFile $StateFile -Code 'PHASE' -Message "WAIT_CDP|$elapsedSec"
                if (-not $QuietConsole -and [string]::IsNullOrWhiteSpace($StateFile)) {
                    Write-Host "      $(Resolve-ZhText '\u4ecd\u5728\u7b49\u5f85\u8c03\u8bd5\u7aef\u53e3\u5c31\u7eea') (${elapsedSec}s)..." -ForegroundColor DarkGray
                }
            }
            Start-Sleep -Milliseconds 300
        }
        if (-not $ready) {
            $errDetail = if ($script:LastCdpError) { " - $($script:LastCdpError)" } else { '' }
            $msg = "$(Resolve-ZhText '\u7b49\u5f85 Antigravity \u8c03\u8bd5\u7aef\u53e3\u5c31\u7eea\u8d85\u65f6 (\u7aef\u53e3:') $port)$errDetail"
            Write-LaunchState -StateFile $StateFile -Code 'ERROR' -Message $msg
            Write-AgyLog -Level 'ERROR' -Message $msg
            throw $msg
        }
    }

    New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null
    [System.IO.File]::WriteAllText($WatcherPidFile, "$PID`n", [System.Text.UTF8Encoding]::new($false))
    Write-LaunchState -StateFile $StateFile -Code 'PHASE' -Message "CDP_READY|$port"
    & $writeStep 'INFO' $TagInfo "$(Resolve-ZhText '[4/4] \u8c03\u8bd5\u7aef\u53e3\u5df2\u5c31\u7eea (\u7aef\u53e3') $port$(Resolve-ZhText ')\uff0c\u6b63\u5728\u8fde\u63a5\u7a97\u53e3\u5e76\u6ce8\u5165\u4e2d\u6587\u754c\u9762...')" ''

    $injectedUrls = @{}
    $loggedTargets = @{}
    $loggedErrors = @{}
    $processTarget = {
        param(
            [object]$TargetObj,
            [string]$EventName = ''
        )
        $tid = [string]$TargetObj.id
        if ([string]::IsNullOrWhiteSpace($tid)) { return }
        $tType = [string]$TargetObj.type
        $tUrl = [string]$TargetObj.url
        $matched = Test-CdpTargetMatch -Target $TargetObj
        $targetKey = "$tid|$tType|$tUrl"
        if (-not $loggedTargets.ContainsKey($targetKey)) {
            $loggedTargets[$targetKey] = $true
            $discMsg = if ($EventName) {
                "Target event ($EventName): id=$tid type=$tType matched=$matched url=$tUrl"
            } else {
                "Target discovered: id=$tid type=$tType matched=$matched url=$tUrl"
            }
            Write-AgyLog -Level 'INFO' -Message $discMsg
            if (-not $matched -and -not [string]::IsNullOrWhiteSpace($tUrl) -and ($tType -notin @('worker', 'service_worker', 'shared_worker', 'background_page'))) {
                Write-LaunchState -StateFile $StateFile -Code 'SKIP' -Message "$tType|$tUrl"
            }
        }
        if (-not $matched) { return }
        try {
            $injectStatus = Invoke-InjectTarget -Target $TargetObj -Port $port -OverlaySource $overlaySource -Fingerprint $fingerprint
            if ($injectStatus -eq 'injected') {
                $wasInjected = $injectedUrls.ContainsKey($tid)
                $injectedUrls[$tid] = $tUrl
                $logVerb = if ($wasInjected) {
                    if ($EventName) { 'Re-injected target from event after reload' } else { 'Re-injected target after reload' }
                } else {
                    if ($EventName) { 'Injected target from event' } else { 'Injected target' }
                }
                Write-AgyLog -Level 'INFO' -Message "${logVerb}: id=$tid type=$tType url=$tUrl"
                Write-LaunchState -StateFile $StateFile -Code 'INJECTED' -Message "$($injectedUrls.Count)|$tUrl"
                if (-not $QuietConsole) {
                    $okMsg = if ($wasInjected) {
                        Resolve-ZhText '\u68c0\u6d4b\u5230\u7a97\u53e3\u91cd\u8f7d\uff0c\u5df2\u81ea\u52a8\u8865\u6ce8\u4e2d\u6587\u754c\u9762'
                    } else {
                        Resolve-ZhText '\u5df2\u5b8c\u6210\u4e2d\u6587\u754c\u9762\u6ce8\u5165'
                    }
                    Write-Host "$TagOk $okMsg ($tUrl)" -ForegroundColor Green
                }
            } elseif ($injectStatus -eq 'already') {
                if (-not $injectedUrls.ContainsKey($tid) -or $injectedUrls[$tid] -ne $tUrl) {
                    $injectedUrls[$tid] = $tUrl
                    Write-LaunchState -StateFile $StateFile -Code 'INJECTED' -Message "$($injectedUrls.Count)|$tUrl"
                }
            }
        } catch {
            $errText = $_.Exception.Message
            $errKey = "$tid|$tUrl|$errText"
            if (-not $loggedErrors.ContainsKey($errKey)) {
                $loggedErrors[$errKey] = $true
                $errPrefix = if ($EventName) { 'Inject failed from event' } else { 'Inject failed' }
                & $writeStep 'WARN' $TagWarn "$errPrefix (id=$tid type=$tType url=$tUrl): $errText" 'Yellow'
                Write-LaunchState -StateFile $StateFile -Code 'WARN' -Message "$tUrl | $errText"
            }
        }
    }
    $sweepTargets = {
        $targets = Invoke-LocalCdpJson -Port $port -Path '/json/list'
        if ($null -ne $targets) {
            foreach ($t in $targets) {
                . $processTarget -TargetObj $t -EventName ''
            }
        }
    }

    $connectBrowser = {
        $ver = Invoke-LocalCdpJson -Port $port -Path '/json/version'
        if ($null -eq $ver -or -not (Test-ValidCdpWsUrl -WsUrl ([string]$ver.webSocketDebuggerUrl) -ExpectedPort $port)) {
            return $null
        }
        $bws = Connect-LocalWebSocket -WsUrl ([string]$ver.webSocketDebuggerUrl)
        $discoverJson = '{"id":1,"method":"Target.setDiscoverTargets","params":{"discover":true}}'
        $dBytes = [System.Text.Encoding]::UTF8.GetBytes($discoverJson)
        $dSeg = [System.ArraySegment[byte]]::new($dBytes)
        $dCts = [System.Threading.CancellationTokenSource]::new(3000)
        try {
            $null = $bws.SendAsync($dSeg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $dCts.Token).GetAwaiter().GetResult()
        } finally {
            $dCts.Dispose()
        }
        return $bws
    }

    $browserWs = $null
    try {
        . $sweepTargets
        $lastConnectErr = ''
        for ($i = 0; $i -lt 15; $i++) {
            try {
                $browserWs = & $connectBrowser
                if ($null -ne $browserWs) { break }
            } catch {
                $lastConnectErr = $_.Exception.Message
            }
            Start-Sleep -Milliseconds 300
        }
        if ($null -eq $browserWs) {
            $connDetail = if ($lastConnectErr) { " - $lastConnectErr" } elseif ($script:LastCdpError) { " - $($script:LastCdpError)" } else { '' }
            $msg = "$(Resolve-ZhText '\u65e0\u6cd5\u5efa\u7acb\u672c\u5730 CDP \u4e8b\u4ef6\u8fde\u63a5 (\u7aef\u53e3:') $port)$connDetail"
            Write-LaunchState -StateFile $StateFile -Code 'ERROR' -Message $msg
            Write-AgyLog -Level 'ERROR' -Message $msg
            throw $msg
        }

        Write-LaunchState -StateFile $StateFile -Code 'PHASE' -Message "WATCHING|$port"
        & $writeStep 'INFO' $TagOk "$(Resolve-ZhText '\u5df2\u8fdb\u5165 Antigravity \u4e2d\u6587\u76d1\u89c6\u72b6\u6001 (\u7aef\u53e3') $port$(Resolve-ZhText ')\u3002')" 'Green'
        $bBuf = New-Object byte[] 65536
        $bSeg = [System.ArraySegment[byte]]::new($bBuf)
        $msgMs = [System.IO.MemoryStream]::new()
        $loopCts = [System.Threading.CancellationTokenSource]::new()
        $recvTask = $browserWs.ReceiveAsync($bSeg, $loopCts.Token)
        $loopStart = [DateTime]::UtcNow
        $lastSweep = $loopStart

        try {
            while ($true) {
                $fastInitial = (([DateTime]::UtcNow - $loopStart).TotalSeconds -lt 15)
                $waitMs = if ($fastInitial) { 500 } else { 1500 }
                $sweepSec = if ($fastInitial) { 0.5 } else { 2.0 }

                $signaled = $false
                try {
                    $signaled = $recvTask.Wait($waitMs)
                } catch {
                    $signaled = $true
                }

                if ($signaled) {
                    $wsBroken = $false
                    try {
                        $r = $recvTask.GetAwaiter().GetResult()
                        if ($r.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                            $wsBroken = $true
                        } else {
                            if ($r.Count -gt 0) { $msgMs.Write($bBuf, 0, $r.Count) }
                            if ($r.EndOfMessage) {
                                $txt = [System.Text.Encoding]::UTF8.GetString($msgMs.GetBuffer(), 0, [int]$msgMs.Length)
                                $msgMs.SetLength(0)
                                try {
                                    $evt = $txt | ConvertFrom-Json
                                    if ($evt.method -eq 'Target.targetDestroyed') {
                                        $null = $injectedUrls.Remove([string]$evt.params.targetId)
                                    } elseif ($evt.method -eq 'Target.targetCreated' -or $evt.method -eq 'Target.targetInfoChanged') {
                                        $info = $evt.params.targetInfo
                                        $tid = [string]$info.targetId
                                        $tType = [string]$info.type
                                        $tUrl = [string]$info.url
                                        if ($tid -and ($evt.method -eq 'Target.targetCreated' -or -not $injectedUrls.ContainsKey($tid) -or $injectedUrls[$tid] -ne $tUrl)) {
                                            $tObj = [PSCustomObject]@{
                                                id                   = $tid
                                                type                 = $tType
                                                url                  = $tUrl
                                                webSocketDebuggerUrl = "ws://127.0.0.1:$port/devtools/page/$tid"
                                            }
                                            . $processTarget -TargetObj $tObj -EventName $evt.method
                                        }
                                    }
                                } catch {}
                            }
                            $recvTask = $browserWs.ReceiveAsync($bSeg, $loopCts.Token)
                        }
                    } catch {
                        $wsBroken = $true
                    }

                    if ($wsBroken) {
                        Write-AgyLog -Level 'WARN' -Message 'CDP browser WebSocket disconnected; attempting reconnect.'
                        try { $loopCts.Cancel() } catch {}
                        try { $browserWs.Dispose() } catch {}
                        $loopCts.Dispose()
                        $msgMs.SetLength(0)
                        $browserWs = $null

                        $reconnected = $false
                        $backoffMs = 500
                        $rcDeadline = [DateTime]::UtcNow.AddSeconds(30)
                        while ([DateTime]::UtcNow -lt $rcDeadline) {
                            if (@(Get-SameSessionAntigravityPids).Count -eq 0 -and $null -eq (Invoke-LocalCdpJson -Port $port -Path '/json/version')) {
                                break
                            }
                            Start-Sleep -Milliseconds $backoffMs
                            try {
                                $browserWs = & $connectBrowser
                                if ($null -ne $browserWs) {
                                    $reconnected = $true
                                    break
                                }
                            } catch {}
                            $backoffMs = [Math]::Min($backoffMs * 2, 5000)
                        }
                        if (-not $reconnected) {
                            Write-AgyLog -Level 'INFO' -Message 'CDP reconnect ended (Antigravity closed).'
                            break
                        }
                        Write-AgyLog -Level 'INFO' -Message 'CDP browser WebSocket reconnected.'
                        $loopCts = [System.Threading.CancellationTokenSource]::new()
                        $recvTask = $browserWs.ReceiveAsync($bSeg, $loopCts.Token)
                        . $sweepTargets
                    }
                }

                if (([DateTime]::UtcNow - $lastSweep).TotalSeconds -ge $sweepSec) {
                    $lastSweep = [DateTime]::UtcNow
                    . $sweepTargets
                    if (@(Get-SameSessionAntigravityPids).Count -eq 0 -and $null -eq (Invoke-LocalCdpJson -Port $port -Path '/json/version')) {
                        Write-AgyLog -Level 'INFO' -Message 'Antigravity process exited; stopping watcher.'
                        break
                    }
                }
            }
        } finally {
            try { $loopCts.Cancel() } catch {}
            try { $loopCts.Dispose() } catch {}
            $msgMs.Dispose()
        }
    } finally {
        if ($null -ne $browserWs) {
            try { $browserWs.Dispose() } catch {}
        }
        try {
            if ((Test-Path $WatcherPidFile) -and ((Get-Content -Raw -Path $WatcherPidFile -ErrorAction SilentlyContinue).Trim() -eq "$PID")) {
                Remove-Item -Force -Path $WatcherPidFile -ErrorAction SilentlyContinue
            }
        } catch {}
    }
}

function Start-GuiManagedLaunch {
    try { $Host.UI.RawUI.WindowTitle = $meta.appName } catch {}
    Reset-AgyLog
    Write-AgyLog -Level 'INFO' -Message "Starting GUI launch ($Lang), PSVersion=$($PSVersionTable.PSVersion)"

    Write-Host ''
    Write-Host "=== $($meta.appName) ===" -ForegroundColor Cyan
    Write-Host (Resolve-ZhText '[1/4] \u6b63\u5728\u51c6\u5907\u4e2d\u6587\u6c49\u5316\u811a\u672c...')
    Build-AgyOverlay -Force $false

    Write-Host (Resolve-ZhText '[2/4] \u6b63\u5728\u68c0\u67e5 Antigravity \u8fd0\u884c\u72b6\u6001\u4e0e\u8bed\u8a00\u63d2\u4ef6...')
    if (-not (Prepare-AntigravityForZhLaunch -GuiMode $true)) {
        Start-Sleep -Seconds 1
        return
    }
    Stop-PreviousLanguageWatchers
    if (Test-Path (Join-Path $PluginDir 'plugin.json')) {
        Set-ZhPluginEnabled -Enabled $true
    }

    $existingPort = Get-DebugAntigravityPort
    $origExe = Find-OriginalExe
    $targetPort = 0
    $needLaunch = $false
    if ($existingPort -gt 0) {
        $targetPort = $existingPort
        Write-Host "$(Resolve-ZhText '[3/4] \u68c0\u6d4b\u5230 Antigravity \u5df2\u5728\u8c03\u8bd5\u6a21\u5f0f\u8fd0\u884c (\u7aef\u53e3') $targetPort$(Resolve-ZhText ')\uff0c\u6b63\u5728\u5524\u9192\u7a97\u53e3\u5e76\u9644\u7740\u6c49\u5316\u76d1\u89c6...')"
        $focused = Focus-VisibleWindowForPids -TargetPids @(Get-SameSessionAntigravityPids)
        if (-not $focused -and $origExe) {
            Write-AgyLog -Level 'INFO' -Message 'Debug port active with no visible window; opening Antigravity window.'
            $null = Start-AntigravityProcess -ExePath $origExe
        }
    } else {
        if (-not $origExe) {
            throw (Resolve-ZhText '\u672a\u627e\u5230 Antigravity.exe \u5b89\u88c5\u8def\u5f84\uff0c\u8bf7\u786e\u8ba4\u5df2\u5b89\u88c5\u5b98\u65b9 Google Antigravity\u3002')
        }
        $targetPort = Get-FreeLoopbackPort
        $needLaunch = $true
        Write-Host "$(Resolve-ZhText '[3/4] \u6b63\u5728\u542f\u52a8 Antigravity \u8c03\u8bd5\u4f1a\u8bdd (\u7aef\u53e3') $targetPort)..."
        Write-Host "      $(Resolve-ZhText '(\u9996\u6b21\u6216\u51b7\u542f\u52a8\u53ef\u80fd\u9700\u8981 5~20 \u79d2\uff0c\u8bf7\u7a0d\u5019...)')" -ForegroundColor DarkGray
    }

    New-Item -ItemType Directory -Force -Path $LogsDir | Out-Null
    Get-ChildItem -Path $LogsDir -Filter 'launch-*.state' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTimeUtc -lt [DateTime]::UtcNow.AddDays(-1) } |
        Remove-Item -Force -ErrorAction SilentlyContinue
    $stateFile = Join-Path $LogsDir ('launch-' + [System.Guid]::NewGuid().ToString('N') + '.state')
    [System.IO.File]::WriteAllText($stateFile, '', [System.Text.UTF8Encoding]::new($false))

    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $selfScript = Join-Path $PSScriptRoot 'agy-zh.ps1'
    $watchArgs = @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', $selfScript, 'watch', '--lang', $Lang, '--port', "$targetPort"
    )
    if ($needLaunch) { $watchArgs += '--launch' }
    $watchArgs += @('--state-file', $stateFile)

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $psExe
    $psi.Arguments = (($watchArgs | ForEach-Object { Format-WinArg $_ }) -join ' ')
    $psi.WorkingDirectory = $PSScriptRoot
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden

    $watcherProc = $null
    $fallbackInProcess = $false
    $spawnError = ''
    try {
        try {
            $watcherProc = [System.Diagnostics.Process]::Start($psi)
        } catch {
            $ex = $_.Exception
            while ($null -ne $ex.InnerException) { $ex = $ex.InnerException }
            $spawnError = $ex.Message
            $fallbackInProcess = $true
        }
        if (-not $fallbackInProcess -and $null -eq $watcherProc) {
            $spawnError = Resolve-ZhText '\u65e0\u6cd5\u542f\u52a8\u540e\u53f0\u6c49\u5316\u76d1\u89c6\u5668\u8fdb\u7a0b\u3002'
            $fallbackInProcess = $true
        }
        if ($fallbackInProcess) {
            Write-AgyLog -Level 'WARN' -Message "Background watcher spawn blocked ($spawnError); falling back to in-process watcher."
            Write-Host "$TagWarn $(Resolve-ZhText '\u68c0\u6d4b\u5230\u7cfb\u7edf\u7b56\u7565\u6216\u5b89\u5168\u8f6f\u4ef6\u9650\u5236\u540e\u53f0\u5b50\u8fdb\u7a0b\u542f\u52a8\uff0c\u5df2\u81ea\u52a8\u5207\u6362\u4e3a\u5f53\u524d\u7a97\u53e3\u76f4\u63a5\u8fd0\u884c\u3002')" -ForegroundColor Yellow
            Write-Host "      $(Resolve-ZhText '\uff08\u6b64\u6a21\u5f0f\u4e0b\u8bf7\u5c06\u672c\u7a97\u53e3\u6700\u5c0f\u5316\u4fdd\u6301\u8fd0\u884c\uff0c\u5173\u95ed\u672c\u7a97\u53e3\u4f1a\u505c\u6b62\u4e2d\u6587\u76d1\u89c6\uff09')" -ForegroundColor DarkGray
            Write-Host "      $(Resolve-ZhText '\u65e5\u5fd7\u6587\u4ef6'): $LogFile" -ForegroundColor DarkGray
            if (Test-Path $stateFile) {
                Remove-Item -Force -Path $stateFile -ErrorAction SilentlyContinue
            }
            Start-CdpWatchLoop -GuiMode $true -FixedPort $targetPort -LaunchApp $needLaunch -QuietConsole $false
            return
        }

        $startTime = [DateTime]::UtcNow
        $processedCount = 0
        $lastWaitSec = -1
        $cdpReadyPrinted = $false
        $watching = $false
        $watchingAt = $null
        $injectedCount = 0
        $lastError = ''
        $warnings = New-Object 'System.Collections.Generic.List[string]'
        $skippedUrls = New-Object 'System.Collections.Generic.List[string]'

        $drainState = {
            $lines = @(Read-LaunchStateLines -StateFile $stateFile)
            while ($processedCount -lt $lines.Count) {
                $line = $lines[$processedCount]
                $processedCount++
                $parts = @($line -split '\|', 2)
                $code = $parts[0]
                $payload = if ($parts.Count -gt 1) { $parts[1] } else { '' }
                if ($code -eq 'PHASE') {
                    $p2 = @($payload -split '\|', 2)
                    $phase = $p2[0]
                    $pval = if ($p2.Count -gt 1) { $p2[1] } else { '' }
                    if ($phase -eq 'WAIT_CDP') {
                        $sec = 0
                        try { $sec = [int]$pval } catch {}
                        if ($sec -gt $lastWaitSec) {
                            $lastWaitSec = $sec
                            Write-Host "      $(Resolve-ZhText '\u4ecd\u5728\u7b49\u5f85\u8c03\u8bd5\u7aef\u53e3\u5c31\u7eea') (${sec}s)..." -ForegroundColor DarkGray
                        }
                    } elseif ($phase -eq 'CDP_READY' -or $phase -eq 'WATCHING') {
                        if (-not $cdpReadyPrinted) {
                            $cdpReadyPrinted = $true
                            Write-Host "$(Resolve-ZhText '[4/4] \u8c03\u8bd5\u7aef\u53e3\u5df2\u5c31\u7eea (\u7aef\u53e3') $targetPort$(Resolve-ZhText ')\uff0c\u6b63\u5728\u8fde\u63a5\u7a97\u53e3\u5e76\u6ce8\u5165\u4e2d\u6587\u754c\u9762...')"
                        }
                        if ($phase -eq 'WATCHING' -and $null -eq $watchingAt) {
                            $watching = $true
                            $watchingAt = [DateTime]::UtcNow
                        }
                    }
                } elseif ($code -eq 'INJECTED') {
                    $p2 = @($payload -split '\|', 2)
                    try { $injectedCount = [int]$p2[0] } catch { $injectedCount = 1 }
                } elseif ($code -eq 'SKIP') {
                    $p2 = @($payload -split '\|', 2)
                    $disp = if ($p2.Count -gt 1) { "[$($p2[0])] $($p2[1])" } else { $payload }
                    if (-not $skippedUrls.Contains($disp)) { $skippedUrls.Add($disp) }
                } elseif ($code -eq 'WARN') {
                    if ($payload -and -not $warnings.Contains($payload)) { $warnings.Add($payload) }
                } elseif ($code -eq 'ERROR') {
                    $lastError = $payload
                }
            }
        }

        while ($true) {
            . $drainState

            if ($watching -and $injectedCount -gt 0) {
                Write-Host ''
                Write-Host "$TagOk $(Resolve-ZhText '\u5df2\u5b8c\u6210\u4e2d\u6587\u754c\u9762\u6ce8\u5165 (\u7aef\u53e3') $targetPort$(Resolve-ZhText ')\uff0c\u540e\u53f0\u6c49\u5316\u76d1\u89c6\u5668\u5df2\u63a5\u7ba1\u8fd0\u884c\u3002')" -ForegroundColor Green
                Write-Host "      $(Resolve-ZhText '\u65e5\u5fd7\u6587\u4ef6'): $LogFile" -ForegroundColor DarkGray
                Write-Host "      $(Resolve-ZhText '\u672c\u7a97\u53e3\u5c06\u5728 2 \u79d2\u540e\u81ea\u52a8\u5173\u95ed...')" -ForegroundColor DarkGray
                Start-Sleep -Seconds 2
                return
            }

            if ($lastError -or $watcherProc.HasExited) {
                Start-Sleep -Milliseconds 200
                . $drainState
                if (-not $lastError) {
                    $lastError = "$(Resolve-ZhText '\u540e\u53f0\u76d1\u89c6\u5668\u610f\u5916\u9000\u51fa (\u9000\u51fa\u7801:') $($watcherProc.ExitCode))."
                }
                Write-Host ''
                Write-Host "$TagErr $lastError" -ForegroundColor Red
                foreach ($w in $warnings) { Write-Host "  [WARN] $w" -ForegroundColor Yellow }
                if ($skippedUrls.Count -gt 0) {
                    Write-Host "  $(Resolve-ZhText '\u5df2\u53d1\u73b0\u4f46\u672a\u5339\u914d\u7684\u9875\u9762\u76ee\u6807:'):" -ForegroundColor Yellow
                    foreach ($su in $skippedUrls) { Write-Host "    - $su" -ForegroundColor Yellow }
                }
                Write-Host "  $(Resolve-ZhText '\u65e5\u5fd7\u6587\u4ef6'): $LogFile" -ForegroundColor DarkGray
                if (Test-Path $LogFile) {
                    $tail = @(Get-Content -Path $LogFile -Tail 10 -Encoding UTF8 -ErrorAction SilentlyContinue)
                    if ($tail.Count -gt 0) {
                        Write-Host "  $(Resolve-ZhText '\u6700\u8fd1\u65e5\u5fd7:'):" -ForegroundColor DarkGray
                        foreach ($tl in $tail) { Write-Host "    $tl" -ForegroundColor DarkGray }
                    }
                }
                $script:GuiFailureHandled = $true
                Pause-GuiConsole -FallbackTitle $meta.appName -FallbackMessage ($meta.appName + ': ' + $lastError)
                throw $lastError
            }

            if ($watching -and $null -ne $watchingAt -and (([DateTime]::UtcNow - $watchingAt).TotalSeconds -ge 12)) {
                Write-Host ''
                Write-Host "$TagWarn $(Resolve-ZhText 'Antigravity \u5df2\u542f\u52a8\u4e14\u8c03\u8bd5\u7aef\u53e3') ($targetPort) $(Resolve-ZhText '\u5df2\u8fde\u63a5\uff0c\u4f46 12 \u79d2\u5185\u672a\u68c0\u6d4b\u5230\u53ef\u6c49\u5316\u7684\u754c\u9762\u76ee\u6807\u3002')" -ForegroundColor Yellow
                foreach ($w in $warnings) { Write-Host "  [WARN] $w" -ForegroundColor Yellow }
                if ($skippedUrls.Count -gt 0) {
                    Write-Host "  $(Resolve-ZhText '\u5df2\u53d1\u73b0\u4f46\u672a\u5339\u914d\u7684\u9875\u9762\u76ee\u6807:'):" -ForegroundColor Yellow
                    foreach ($su in $skippedUrls) { Write-Host "    - $su" -ForegroundColor Yellow }
                } else {
                    Write-Host "  $(Resolve-ZhText '\u6682\u672a\u53d1\u73b0\u53ef\u6ce8\u5165\u7684\u9875\u9762\u76ee\u6807\uff08\u53ef\u80fd\u7a97\u53e3\u5c1a\u672a\u521b\u5efa\u6216\u53d7\u5230\u5b89\u5168\u7b56\u7565\u963b\u62e6\uff09\u3002')" -ForegroundColor Yellow
                }
                Write-Host "  $(Resolve-ZhText '\u65e5\u5fd7\u6587\u4ef6'): $LogFile" -ForegroundColor DarkGray
                Write-Host "  $(Resolve-ZhText '\u540e\u53f0\u76d1\u89c6\u5668\u4ecd\u5728\u8fd0\u884c\uff1b\u82e5\u7a0d\u540e\u754c\u9762\u4ecd\u4e3a\u82f1\u6587\uff0c\u8bf7\u5c06\u4ee5\u4e0a\u4fe1\u606f\u6216\u65e5\u5fd7\u622a\u56fe\u53cd\u9988\u3002')"
                Pause-GuiConsole
                return
            }

            if (-not $watching -and ([DateTime]::UtcNow - $startTime).TotalSeconds -ge 45) {
                try {
                    if (-not $watcherProc.HasExited) { Stop-Process -Id $watcherProc.Id -Force -ErrorAction SilentlyContinue }
                } catch {}
                $timeoutMsg = "$(Resolve-ZhText '\u542f\u52a8\u8d85\u65f6 (45s)\uff1a\u672a\u80fd\u5b8c\u6210\u4e0e Antigravity \u8c03\u8bd5\u7aef\u53e3') ($targetPort) $(Resolve-ZhText '\u7684\u8fde\u63a5\u3002')"
                Write-AgyLog -Level 'ERROR' -Message $timeoutMsg
                Write-Host ''
                Write-Host "$TagErr $timeoutMsg" -ForegroundColor Red
                Write-Host "  $(Resolve-ZhText '\u65e5\u5fd7\u6587\u4ef6'): $LogFile" -ForegroundColor DarkGray
                if (Test-Path $LogFile) {
                    $tail = @(Get-Content -Path $LogFile -Tail 10 -Encoding UTF8 -ErrorAction SilentlyContinue)
                    foreach ($tl in $tail) { Write-Host "    $tl" -ForegroundColor DarkGray }
                }
                $script:GuiFailureHandled = $true
                Pause-GuiConsole -FallbackTitle $meta.appName -FallbackMessage ($meta.appName + ': ' + $timeoutMsg)
                throw $timeoutMsg
            }

            Start-Sleep -Milliseconds 250
        }
    } finally {
        if ($null -ne $watcherProc) {
            try { $watcherProc.Dispose() } catch {}
        }
        if (Test-Path $stateFile) {
            Remove-Item -Force -Path $stateFile -ErrorAction SilentlyContinue
        }
    }
}

function New-ZhShortcut {
    $targets = @(
        ([Environment]::GetFolderPath('Desktop')),
        ([Environment]::GetFolderPath('Programs'))
    )
    $wsh = New-Object -ComObject WScript.Shell
    $vbsName = if ($Lang -eq 'zh-CN') { 'agy-zh-launch.vbs' } else { $meta.command + '-launch.vbs' }
    $vbsPath = Join-Path $PSScriptRoot $vbsName
    if (Test-Path $vbsPath) {
        Remove-Item -Force -Path $vbsPath -ErrorAction SilentlyContinue
    }
    $origExe = Find-OriginalExe
    $desc = $meta.appName + ' (' + $Lang + ')'
    $psExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $scriptPath = Join-Path $PSScriptRoot 'agy-zh.ps1'

    foreach ($dir in $targets) {
        if ([string]::IsNullOrWhiteSpace($dir)) { continue }
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $lnkPath = Join-Path $dir $ShortcutName
        $sc = $wsh.CreateShortcut($lnkPath)
        $sc.TargetPath = $psExe
        $sc.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" start --lang $Lang --gui"
        $sc.WorkingDirectory = $PSScriptRoot
        $sc.WindowStyle = 1
        if ($origExe) {
            $sc.IconLocation = "$origExe,0"
        }
        $sc.Description = $desc
        $sc.Save()
        Write-Host "$TagOk $(Resolve-ZhText '\u5df2\u521b\u5efa\u300cAntigravity \u4e2d\u6587\u300d\u5feb\u6377\u65b9\u5f0f:') $lnkPath"
    }
}

$watchPort = 0
$watchLaunch = $false
$watchStateFile = ''
$cmdLower = $SubCommand.ToLowerInvariant()
if ($cmdLower -eq 'watch') {
    for ($i = 0; $i -lt $RestArgs.Count; $i++) {
        $arg = $RestArgs[$i]
        if ($arg -eq '--port') {
            if (++$i -ge $RestArgs.Count) { throw '--port requires a port number.' }
            $parsedPort = 0
            if (-not [int]::TryParse($RestArgs[$i], [ref]$parsedPort) -or $parsedPort -le 0 -or $parsedPort -gt 65535) {
                throw "Invalid --port: $($RestArgs[$i])"
            }
            $watchPort = $parsedPort
        } elseif ($arg -eq '--launch') {
            $watchLaunch = $true
        } elseif ($arg -eq '--state-file') {
            if (++$i -ge $RestArgs.Count -or [string]::IsNullOrWhiteSpace($RestArgs[$i])) {
                throw '--state-file requires a path.'
            }
            $watchStateFile = $RestArgs[$i]
        } else {
            throw "Unsupported argument: $arg"
        }
    }
} else {
    $allowed = switch ($cmdLower) {
        'start' { @('--gui', '--nogui') }
        'build-overlay' { @('--force') }
        'prompt' { @('on','off','status') }
        { $_ -in @('stop','status','shortcut','help') } { @() }
        default { throw "Unknown command: $SubCommand. Use agy-zh help." }
    }
    foreach ($arg in $RestArgs) { if ($arg -notin $allowed) { throw "Unsupported argument: $arg" } }
}
if ($SubCommand -eq 'prompt' -and $RestArgs.Count -gt 1) { throw 'Usage: agy-zh prompt <on|off|status>' }
if ($SubCommand -eq 'help') {
    Write-Host 'agy-zh [start|stop|status|prompt <on|off|status>|build-overlay [--force]|shortcut] [--lang <code>]'
    Write-Host 'Languages: zh-CN zh-TW ja ko es fr de ru pt-BR (default: zh-CN)'
    return
}
switch ($cmdLower) {
    'start' {
        $isGuiMode = ($RestArgs -contains '--gui' -or $RestArgs -contains '--nogui')
        try {
            if ($isGuiMode) {
                Start-GuiManagedLaunch
            } else {
                Reset-AgyLog
                Write-AgyLog -Level 'INFO' -Message "Starting CLI launch ($Lang), PSVersion=$($PSVersionTable.PSVersion)"
                Write-Host (Resolve-ZhText '[1/4] \u6b63\u5728\u51c6\u5907\u4e2d\u6587\u6c49\u5316\u811a\u672c...')
                Build-AgyOverlay -Force $false
                Write-Host (Resolve-ZhText '[2/4] \u6b63\u5728\u68c0\u67e5 Antigravity \u8fd0\u884c\u72b6\u6001\u4e0e\u8bed\u8a00\u63d2\u4ef6...')
                if (-not (Prepare-AntigravityForZhLaunch -GuiMode $false)) {
                    break
                }
                Stop-PreviousLanguageWatchers
                if (Test-Path (Join-Path $PluginDir 'plugin.json')) {
                    Set-ZhPluginEnabled -Enabled $true
                }
                Start-CdpWatchLoop -GuiMode $false
            }
        } finally {
            Start-Sleep -Milliseconds 300
            if (-not (Test-ActiveWatcher)) {
                Set-ZhPluginEnabled -Enabled $false
            }
        }
    }
    'watch' {
        try {
            Start-CdpWatchLoop -GuiMode $true -FixedPort $watchPort -LaunchApp $watchLaunch -StateFile $watchStateFile -QuietConsole $true
        } catch {
            $errMsg = $_.Exception.Message
            Write-AgyLog -Level 'ERROR' -Message "Watch loop error: $errMsg"
            Write-LaunchState -StateFile $watchStateFile -Code 'ERROR' -Message $errMsg
            throw
        } finally {
            Start-Sleep -Milliseconds 300
            if (-not (Test-ActiveWatcher)) {
                Set-ZhPluginEnabled -Enabled $false
            }
        }
    }
    'build-overlay' {
        $forceFlag = ($RestArgs -contains '--force')
        Build-AgyOverlay -Force $forceFlag
        Write-Host "$TagOk $(Resolve-ZhText '\u5df2\u751f\u6210\u589e\u5f3a\u6c49\u5316\u8986\u76d6\u811a\u672c:') $OverlayJs"
    }
    'stop' {
        foreach ($wpid in @(Get-ActiveWatcherPids)) {
            Stop-Process -Id $wpid -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path $WatcherPidFile) {
            Remove-Item -Force -Path $WatcherPidFile -ErrorAction SilentlyContinue
        }
        Set-ZhPluginEnabled -Enabled $false
        Write-Host "$TagOk $(Resolve-ZhText '\u5df2\u505c\u6b62\u4e2d\u6587\u6c49\u5316\u76d1\u89c6\u5668\uff0c\u5e76\u5173\u95ed\u4e2d\u6587\u601d\u8003\u63d0\u793a\u8bcd\u63d2\u4ef6\u3002')"
    }
    'prompt' {
        $act = if ($RestArgs.Count -gt 0) { $RestArgs[0].ToLowerInvariant() } else { 'status' }
        switch ($act) {
            'on' {
                Set-ZhPluginEnabled -Enabled $true
                Write-Host "$TagOk $(Resolve-ZhText '\u5df2\u5f00\u542f\u4e2d\u6587\u601d\u8003\u63d0\u793a\u8bcd\u63d2\u4ef6 (antigravity-zh-prompt)\u3002')"
            }
            'off' {
                Set-ZhPluginEnabled -Enabled $false
                Write-Host "$TagOk $(Resolve-ZhText '\u5df2\u5173\u95ed\u4e2d\u6587\u601d\u8003\u63d0\u793a\u8bcd\u63d2\u4ef6 (antigravity-zh-prompt)\u3002')"
            }
            'status' {
                $st = Get-ZhPluginEnabled
                if ($st) {
                    Write-Host (Resolve-ZhText '\u63d0\u793a\u8bcd\u63d2\u4ef6 (antigravity-zh-prompt): \u5df2\u5f00\u542f (enabled: true)')
                } else {
                    Write-Host (Resolve-ZhText '\u63d0\u793a\u8bcd\u63d2\u4ef6 (antigravity-zh-prompt): \u5df2\u5173\u95ed (enabled: false)')
                }
            }
            default {
                throw (Resolve-ZhText '\u7528\u6cd5: agy-zh prompt <on|off|status>')
            }
        }
    }
    'shortcut' {
        New-ZhShortcut
    }
    'status' {
        $orig = Find-OriginalExe
        $st = Get-ZhPluginEnabled
        $activePids = @(Get-ActiveWatcherPids)
        $desktopLnk = Join-Path ([Environment]::GetFolderPath('Desktop')) $ShortcutName
        $programsLnk = Join-Path ([Environment]::GetFolderPath('Programs')) $ShortcutName
        $lnkList = @()
        if (Test-Path $desktopLnk) { $lnkList += $desktopLnk }
        if (Test-Path $programsLnk) { $lnkList += $programsLnk }

        Write-Host "Language: $Lang / $($meta.appName)"
        Write-Host (Resolve-ZhText '=== Antigravity \u53cc\u5165\u53e3\u6c49\u5316\u72b6\u6001 ===')
        Write-Host "$(Resolve-ZhText '\u539f\u7248\u5165\u53e3 (\u7eaf\u51c0\u82f1\u6587): ') $(if ($orig) { $orig } else { Resolve-ZhText '\u672a\u68c0\u6d4b\u5230 Antigravity.exe' })"
        Write-Host "$(Resolve-ZhText '\u4e2d\u6587\u5165\u53e3 (\u53cc\u6548\u8054\u52a8): ') $(if ($lnkList.Count -gt 0) { $lnkList -join '; ' } else { Resolve-ZhText '\u672a\u521b\u5efa\uff08\u53ef\u8fd0\u884c agy-zh shortcut \u751f\u6210\uff09' })"
        Write-Host (Resolve-ZhText '\u672c\u5730 CDP \u6ce8\u5165\u5f15\u64ce  : \u5185\u7f6e\u7eaf PowerShell \u811a\u672c\u5f15\u64ce\uff08\u65e0 .exe \u4e8c\u8fdb\u5236\uff0c\u96f6\u8bef\u62a5\uff09')
        Write-Host "$(Resolve-ZhText '\u589e\u5f3a\u6c49\u5316\u8986\u76d6\u811a\u672c   : ') $(if (Test-Path $OverlayJs) { "$(Resolve-ZhText '\u5df2\u5c31\u7eea ')($OverlayJs)" } else { Resolve-ZhText '\u672a\u751f\u6210\uff08\u53ef\u8fd0\u884c agy-zh build-overlay \u751f\u6210\uff09' })"
        Write-Host "$(Resolve-ZhText '\u4e2d\u6587\u601d\u8003\u63d0\u793a\u8bcd\u63d2\u4ef6 : ') $(if (Test-Path (Join-Path $PluginDir 'plugin.json')) { "$(Resolve-ZhText '\u5df2\u5b89\u88c5 ')($PluginDir)" } else { Resolve-ZhText '\u672a\u5b89\u88c5' })"
        Write-Host "$(Resolve-ZhText '\u63d0\u793a\u8bcd\u5f53\u524d\u5f00\u5173\u72b6\u6001 : ') $(if ($st) { Resolve-ZhText '\u5df2\u5f00\u542f (enabled: true)' } else { Resolve-ZhText '\u5df2\u5173\u95ed (enabled: false\uff0c\u539f\u7248\u5165\u53e3\u7eaf\u51c0)' })"
        Write-Host "$(Resolve-ZhText '\u540e\u53f0\u6c49\u5316\u76d1\u89c6\u5668\u8fdb\u7a0b : ') $(if ($activePids.Count -gt 0) { "$(Resolve-ZhText '\u8fd0\u884c\u4e2d') (PID: $($activePids -join ', '))" } else { Resolve-ZhText '\u672a\u8fd0\u884c' })"
        Write-Host "$(Resolve-ZhText '\u8fd0\u884c\u65e5\u5fd7\u6587\u4ef6       : ') $LogFile"
    }
    default {
        Write-Host (Resolve-ZhText 'agy-zh - Antigravity \u53cc\u5165\u53e3\u65e0\u635f\u6c49\u5316\u4e0e\u4e2d\u6587\u601d\u8003\u63d0\u793a\u8bcd\u8054\u52a8\u542f\u52a8\u5668 (Windows)')
        Write-Host (Resolve-ZhText '\u7528\u6cd5: agy-zh <start|stop|status|prompt <on|off|status>|build-overlay|shortcut>')
    }
}
} catch {
    $errMsg = $_.Exception.Message
    Write-AgyLog -Level 'ERROR' -Message "Fatal error: $errMsg"
    if ($script:IsGuiLaunch) {
        if (-not $script:GuiFailureHandled) {
            $title = if ($null -ne $meta -and $meta.appName) { $meta.appName } else { 'Antigravity' }
            Write-Host ''
            Write-Host "$TagErr $errMsg" -ForegroundColor Red
            if ($script:LogFile) {
                Write-Host "  $(Resolve-ZhText '\u65e5\u5fd7\u6587\u4ef6'): $($script:LogFile)" -ForegroundColor DarkGray
            }
            Pause-GuiConsole -FallbackTitle $title -FallbackMessage ($title + ': ' + $errMsg)
        }
        exit 1
    }
    throw
}