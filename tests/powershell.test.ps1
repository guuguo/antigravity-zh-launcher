$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
foreach ($file in @('install.ps1','uninstall.ps1','bin/agy-zh.ps1','lib/options.ps1','lib/locale.ps1','lib/zh-overlay.ps1')) {
    $tokens = $null; $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $file), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "$file : $($errors.Message -join '; ')" }
    Write-Host "PASS syntax: $file"
}
$psLauncher = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'bin/agy-zh.ps1')
if ($psLauncher -match 'return\s*,\s*\$pids') { throw 'Nested PID array regression in bin/agy-zh.ps1' }
if ($psLauncher -match '/IM\s+Antigravity\.exe') { throw 'Unscoped /IM taskkill regression in bin/agy-zh.ps1' }
if ($psLauncher -match 'wscript\.exe' -or $psLauncher -match '//B') { throw 'Legacy VBS/wscript shortcut regression in bin/agy-zh.ps1' }
if ($psLauncher -notmatch 'DnsSafeHost') { throw 'Missing IPv6 DnsSafeHost fix in bin/agy-zh.ps1' }
if ($psLauncher -notmatch 'CreateNoWindow') { throw 'Missing detached CreateNoWindow watcher launch in bin/agy-zh.ps1' }
if ($psLauncher -match '\.Split\(@\(') { throw 'PowerShell 5.1 String.Split(string[], StringSplitOptions) overload regression in bin/agy-zh.ps1' }
if ($psLauncher -match '&\s+\$drainState\b' -or $psLauncher -notmatch '\.\s+\$drainState\b') { throw 'Child-scope $drainState invocation regression in bin/agy-zh.ps1' }
if ($psLauncher -notmatch 'falling back to in-process watcher') { throw 'Missing in-process watcher fallback for policy-blocked child spawn in bin/agy-zh.ps1' }
if ($psLauncher -notmatch 'Start-AntigravityProcess') { throw 'Missing Start-AntigravityProcess redirection helper in bin/agy-zh.ps1' }
if ($psLauncher -notmatch 'Re-injected target after reload') { throw 'Missing same-URL reload re-injection logging in bin/agy-zh.ps1' }
if ($psLauncher -match '&\s+\$sweepTargets\b' -or $psLauncher -notmatch '\.\s+\$sweepTargets\b') { throw 'Child-scope $sweepTargets invocation regression in bin/agy-zh.ps1' }
if ($psLauncher.Contains('if ($injectedUrls.ContainsKey($tid) -and $injectedUrls[$tid] -eq $tUrl) { continue }')) {
    throw 'Stale same-URL sweep skip regression in bin/agy-zh.ps1'
}
if ($psLauncher -notmatch 'https://raw\.githubusercontent\.com/yuexps/Antigravity-Hans/main/resources/antigravity-hans-overlay\.js') {
    throw 'Missing updated resources/antigravity-hans-overlay.js URL in bin/agy-zh.ps1'
}
if ($psLauncher -match '/Antigravity-Hans/main/antigravity-hans-overlay\.js') {
    throw 'Stale root antigravity-hans-overlay.js URL remains in bin/agy-zh.ps1'
}
$localeLibText = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'lib/locale.ps1')
if ($localeLibText -match '\?\.') { throw 'PS7 null-conditional regression in lib/locale.ps1' }
$zhOverlayLibText = Get-Content -Raw -Encoding UTF8 (Join-Path $root 'lib/zh-overlay.ps1')
if ($zhOverlayLibText -match '\$[A-Za-z0-9_:]+\?\.') { throw 'PS7 null-conditional regression in lib/zh-overlay.ps1' }
. (Join-Path $root 'lib/options.ps1')
foreach ($lang in @('zh-CN','zh-TW','ja','ko','es','fr','de','ru','pt-BR')) {
    $result = Read-AgyOptions -Arguments @('--lang',$lang,'--dry-run') -Switches @('--dry-run')
    if ($result.Lang -cne $lang -or -not $result.dryrun) { throw "Argument parser failed: $lang" }
}
foreach ($bad in @(@('--lang'),@('--lang','en'),@('--unknown'))) {
    $failed = $false
    try { Read-AgyOptions -Arguments $bad | Out-Null } catch { $failed = $true }
    if (-not $failed) { throw "Invalid arguments accepted: $bad" }
}
if ((Read-AgyOptions -Arguments @()).Lang -cne 'zh-CN') { throw 'Default language changed' }
Write-Host 'PASS language arguments, defaults, rejected invalid inputs'
$splitParts = @('PHASE|APP_LAUNCHED|58321' -split '\|', 2)
if ($splitParts.Count -ne 2 -or $splitParts[0] -ne 'PHASE' -or $splitParts[1] -ne 'APP_LAUNCHED|58321') {
    throw 'Launch state -split regression'
}
$dotCount = 0
$dotSb = { $dotCount++ }
. $dotSb
if ($dotCount -ne 1) { throw 'Dot-sourced state drain scope regression' }
# Build all nine overlays offline, including legacy Chinese anchor fallback.
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('agy-ps-test-' + [Guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory $tempRoot | Out-Null
    $AssetRoot = $root
    . (Join-Path $root 'lib/locale.ps1')
    . (Join-Path $root 'lib/zh-overlay.ps1')
    $BaseOverlayJs = Join-Path $tempRoot 'base.js'
    $OverlayVersion = 'agy-zh-v8'
    [IO.File]::WriteAllText($BaseOverlayJs, ('window.__antigravityZhPatchInstalled = true;' + (' ' * 1100)))
    foreach ($Lang in @('zh-CN','zh-TW','ja','ko','es','fr','de','ru','pt-BR')) {
        $OverlayJs = Join-Path $tempRoot ($Lang + '.js')
        Build-AgyOverlay
        & node --check $OverlayJs
        if ($LASTEXITCODE -ne 0) { throw "Invalid generated overlay: $Lang" }
        Write-Host "PASS PowerShell overlay build: $Lang"
    }
    $Lang = 'zh-CN'
    $BaseOverlayJs = Join-Path $tempRoot 'missing-base.js'
    $OverlayJs = Join-Path $tempRoot 'fallback-zh-CN.js'
    $OverlayUrl = 'http://127.0.0.1:1/missing-antigravity-hans-overlay.js'
    Build-AgyOverlay -Force $true
    if (-not (Test-Path $OverlayJs)) { throw 'Fallback zh-CN overlay was not created' }
    if (-not ([IO.File]::ReadAllText($OverlayJs, [Text.Encoding]::UTF8).Contains('__antigravityZhPatchInstalled'))) {
        throw 'Fallback zh-CN overlay missing patch marker'
    }
    & node --check $OverlayJs
    if ($LASTEXITCODE -ne 0) { throw 'Invalid fallback zh-CN overlay' }
    Write-Host 'PASS PowerShell zh-CN fallback when upstream download fails'
} finally { if (Test-Path $tempRoot) { Remove-Item -Recurse -Force $tempRoot } }
# Exercise real entry-point parsing without Windows COM or the Antigravity process.
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('agy-entry-test-' + [Guid]::NewGuid().ToString('N'))
$oldLocal = $env:LOCALAPPDATA; $oldProfile = $env:USERPROFILE; $oldSystemRoot = $env:SystemRoot; $oldConfig = $env:GEMINI_CONFIG_DIR
try {
    New-Item -ItemType Directory $tempRoot | Out-Null
    $env:LOCALAPPDATA = $tempRoot; $env:USERPROFILE = $tempRoot; $env:SystemRoot = $tempRoot; $env:GEMINI_CONFIG_DIR = Join-Path $tempRoot 'config'
    foreach ($lang in @('zh-CN','zh-TW','ja','ko','es','fr','de','ru','pt-BR')) {
        & (Join-Path $root 'install.ps1') --lang $lang --dry-run
        & (Join-Path $root 'uninstall.ps1') --lang $lang --dry-run
    }
    & (Join-Path $root 'bin/agy-zh.ps1') --help
    & (Join-Path $root 'bin/agy-zh.ps1') prompt on --lang ja
    & (Join-Path $root 'bin/agy-zh.ps1') --lang ko prompt on
    $data = Get-Content -Raw -Encoding UTF8 (Join-Path $env:GEMINI_CONFIG_DIR 'config.json') | ConvertFrom-Json
    if ($data.plugins.'antigravity-ja-prompt'.enabled -ne $false -or $data.plugins.'antigravity-ko-prompt'.enabled -ne $true) {
        throw 'Language prompt mutual exclusion failed'
    }
    Write-Host 'PASS nine-language installer/uninstaller dry-runs and runtime prompt selection'
} finally {
    $env:LOCALAPPDATA = $oldLocal; $env:USERPROFILE = $oldProfile; $env:SystemRoot = $oldSystemRoot; $env:GEMINI_CONFIG_DIR = $oldConfig
    if (Test-Path $tempRoot) { Remove-Item -Recurse -Force $tempRoot }
}
