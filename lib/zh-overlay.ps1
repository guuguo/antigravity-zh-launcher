function Resolve-OverlayUnicode {
    param([string]$Text)
    return [regex]::Replace($Text, '\\u([0-9a-fA-F]{4})', {
        param($m)
        [char][convert]::ToInt32($m.Groups[1].Value, 16)
    })
}

function Add-LineIndent {
    param(
        [string]$Text,
        [string]$Indent
    )
    if ([string]::IsNullOrEmpty($Indent)) { return $Text }
    $lines = $Text -split "`n"
    return (($lines | ForEach-Object { if ([string]::IsNullOrEmpty($_)) { '' } else { $Indent + $_ } }) -join "`n")
}

function Replace-FirstMatch {
    param(
        [string]$Text,
        [array]$Variants,
        [string]$Label
    )
    $hits = @()
    $counts = @()
    foreach ($variant in $Variants) {
        $target = [string]$variant.Target
        $idx = $Text.IndexOf($target, [System.StringComparison]::Ordinal)
        if ($idx -lt 0) {
            $counts += 0
            continue
        }
        $second = $Text.IndexOf($target, $idx + $target.Length, [System.StringComparison]::Ordinal)
        if ($second -ge 0) {
            throw "Enhanced overlay anchor matched multiple times: $Label"
        }
        $counts += 1
        $hits += $variant
    }
    if ($hits.Count -ne 1) {
        throw "Enhanced overlay anchor mismatch ($Label): counts=$($counts -join ',')"
    }
    $hit = $hits[0]
    $hitTarget = [string]$hit.Target
    $hitIdx = $Text.IndexOf($hitTarget, [System.StringComparison]::Ordinal)
    return $Text.Substring(0, $hitIdx) + [string]$hit.Replacement + $Text.Substring($hitIdx + $hitTarget.Length)
}

function Replace-Once {
    param(
        [string]$Text,
        [string]$Target,
        [string]$Replacement,
        [string]$Label
    )
    return Replace-FirstMatch -Text $Text -Variants @(@{ Target = $Target; Replacement = $Replacement }) -Label $Label
}

function Ensure-BaseOverlay {
    param([bool]$Refresh = $false)
    if (-not $Refresh -and (Test-Path $BaseOverlayJs) -and ((Get-Item $BaseOverlayJs).Length -gt 1024)) {
        return $true
    }
    $dir = Split-Path -Parent $BaseOverlayJs
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $tmpJs = Join-Path $dir ('.antigravity-hans-overlay.base.' + [System.Guid]::NewGuid().ToString('N') + '.tmp')
    $tag = if ($TagInfo) { $TagInfo } else { '[INFO]' }
    $downloadUrl = if ($OverlayUrl) {
        $OverlayUrl
    } elseif ($env:AGY_ZH_OVERLAY_URL) {
        $env:AGY_ZH_OVERLAY_URL
    } else {
        'https://raw.githubusercontent.com/yuexps/Antigravity-Hans/main/resources/antigravity-hans-overlay.js'
    }
    try {
        Write-Host "$tag $(Resolve-OverlayUnicode '\u6b63\u5728\u4e0b\u8f7d\u57fa\u7840\u6c49\u5316\u8bcd\u5e93\u811a\u672c...')"
        Invoke-WebRequest -UseBasicParsing -Uri $downloadUrl -OutFile $tmpJs -TimeoutSec 20
        $check = [System.IO.File]::ReadAllText($tmpJs, [System.Text.Encoding]::UTF8)
        if (-not $check.Contains('__antigravityZhPatchInstalled')) {
            throw (Resolve-OverlayUnicode '\u4e0b\u8f7d\u7684\u57fa\u7840\u6c49\u5316\u811a\u672c\u6821\u9a8c\u5931\u8d25\u3002')
        }
        Move-Item -Force $tmpJs $BaseOverlayJs
        return $true
    } catch {
        $errMsg = $_.Exception.Message
        if (Get-Command Write-AgyLog -ErrorAction SilentlyContinue) {
            Write-AgyLog -Level 'WARN' -Message "Failed to fetch base overlay from ${downloadUrl}: $errMsg"
        }
        if ((Test-Path $BaseOverlayJs) -and ((Get-Item $BaseOverlayJs).Length -gt 1024)) {
            Write-Warning (Resolve-OverlayUnicode '\u62c9\u53d6\u4e0a\u6e38\u57fa\u7840\u8bcd\u5e93\u5931\u8d25\uff0c\u7ee7\u7eed\u4f7f\u7528\u672c\u5730\u7f13\u5b58\u8bcd\u5e93\u3002')
            return $true
        }
        Write-Warning (Resolve-OverlayUnicode '\u62c9\u53d6\u4e0a\u6e38\u57fa\u7840\u8bcd\u5e93\u5931\u8d25\uff0c\u5df2\u81ea\u52a8\u964d\u7ea7\u4f7f\u7528\u5185\u7f6e\u7b80\u4f53\u4e2d\u6587\u8bcd\u5e93\u3002')
        return $false
    } finally {
        if (Test-Path $tmpJs) { Remove-Item -Force -Path $tmpJs -ErrorAction SilentlyContinue }
    }
}

function Ensure-EnhancedOverlay {
    param([bool]$Force = $false)
    if (-not (Ensure-BaseOverlay -Refresh $Force)) {
        return $false
    }
    $baseHash = (Get-FileHash -Algorithm SHA256 -Path $BaseOverlayJs).Hash.ToLowerInvariant().Substring(0, 16)
    $headerComment = "// antigravity-zh-launcher overlay: $OverlayVersion; base_sha256=$baseHash"
    if (-not $Force -and (Test-Path $OverlayJs)) {
        try {
            $firstLine = Get-Content -Path $OverlayJs -TotalCount 1 -Encoding UTF8 -ErrorAction SilentlyContinue
            if ($firstLine -eq $headerComment) { return $true }
        } catch {}
    }

    $rawJs = [System.IO.File]::ReadAllText($BaseOverlayJs, [System.Text.Encoding]::UTF8)
    $js = $rawJs.Replace("`r`n", "`n")

    try {
        $phrasesAddon = @(
            '  const phrases = new Map([',
            '    ["Ask anything, @ to mention, / for actions", "\u60f3\u95ee\u4ec0\u4e48\u90fd\u53ef\u4ee5\uff0c@ \u5f15\u7528\uff0c/ \u6267\u884c\u52a8\u4f5c"],',
            '    ["Ask anything, @ to mention", "\u60f3\u95ee\u4ec0\u4e48\u90fd\u53ef\u4ee5\uff0c@ \u5f15\u7528"],',
            '    ["Message subagent, @ to mention, / for actions", "\u5411\u5b50\u667a\u80fd\u4f53\u53d1\u6d88\u606f\uff0c@ \u5f15\u7528\uff0c/ \u6267\u884c\u52a8\u4f5c"],',
            '    ["Message subagent, @ to mention", "\u5411\u5b50\u667a\u80fd\u4f53\u53d1\u6d88\u606f\uff0c@ \u5f15\u7528"],',
            '    ["Listening. Ask anything.", "\u6b63\u5728\u8046\u542c\uff0c\u60f3\u95ee\u4ec0\u4e48\u90fd\u53ef\u4ee5\u3002"],',
            '    ["Analyzed", "\u5df2\u5206\u6790"],',
            '    ["Analyzing", "\u6b63\u5728\u5206\u6790"],',
            '    ["Editing", "\u6b63\u5728\u7f16\u8f91"],',
            '    ["Creating", "\u6b63\u5728\u521b\u5efa"],',
            '    ["Created", "\u5df2\u521b\u5efa"],',
            '    ["Updating", "\u6b63\u5728\u66f4\u65b0"],',
            '    ["Updated", "\u5df2\u66f4\u65b0"],',
            '    ["Deleting", "\u6b63\u5728\u5220\u9664"],',
            '    ["Reading", "\u6b63\u5728\u8bfb\u53d6"],',
            '    ["Writing", "\u6b63\u5728\u5199\u5165"],',
            '    ["Wrote", "\u5df2\u5199\u5165"],',
            '    ["Listing", "\u6b63\u5728\u5217\u51fa"],',
            '    ["Listed", "\u5df2\u5217\u51fa"],',
            '    ["Checking", "\u6b63\u5728\u68c0\u67e5"],',
            '    ["Checked", "\u5df2\u68c0\u67e5"],',
            '    ["Viewing", "\u6b63\u5728\u67e5\u770b"],',
            '    ["Viewed", "\u5df2\u67e5\u770b"],',
            '    ["Exploring", "\u6b63\u5728\u63a2\u7d22"],',
            '    ["Invoking", "\u6b63\u5728\u8c03\u7528"],',
            '    ["Invoked", "\u5df2\u8c03\u7528"],',
            '    ["Started", "\u5df2\u5f00\u59cb"],',
            '    ["Starting", "\u6b63\u5728\u542f\u52a8"],',
            '    ["Task Log", "\u4efb\u52a1\u65e5\u5fd7"],',
            '    ["Finished", "\u5df2\u5b8c\u6210"],',
            '    ["finished", "\u5df2\u5b8c\u6210"],'
        ) -join "`n"
        $js = Replace-Once -Text $js -Target '  const phrases = new Map([' -Replacement $phrasesAddon -Label 'phrases'

        $dynEntries = Resolve-OverlayUnicode (@(
            '  [/^(\d+)\s*s\s+ago$/i, ''$1\u79d2\u524d''],',
            '  [/^(\d+)\s*m\s+ago$/i, ''$1\u5206\u949f\u524d''],',
            '  [/^(\d+)\s*h\s+ago$/i, ''$1\u5c0f\u65f6\u524d''],',
            '  [/^(\d+)\s*d\s+ago$/i, ''$1\u5929\u524d''],',
            '  [/^(\d+)\s*w\s+ago$/i, ''$1\u5468\u524d''],',
            '  [/^(\d+)\s*mo\s+ago$/i, ''$1\u4e2a\u6708\u524d''],',
            '  [/^(\d+)\s*y\s+ago$/i, ''$1\u5e74\u524d''],',
            '  [/^(?:Just now|now)$/i, ''\u521a\u521a''],',
            '  [/^(Analyzed|Analyzing|Editing|Edited|Creating|Created|Updating|Updated|Deleting|Deleted|Reading|Writing|Wrote|Listing|Listed|Checking|Checked|Viewing|Viewed)\s+(Task\s+Logs?|[^\r\n]+?(?:\.[A-Za-z0-9]{1,8}(?:\s+#L\d+(?:-\d+)?)?|\s+#L\d+(?:-\d+)?)|[^\s\r\n]+)$/i, (_m, verb, target) => {',
            '    const verbMap = {',
            '      analyzed: ''\u5df2\u5206\u6790'', analyzing: ''\u6b63\u5728\u5206\u6790'', editing: ''\u6b63\u5728\u7f16\u8f91'', edited: ''\u5df2\u7f16\u8f91'',',
            '      creating: ''\u6b63\u5728\u521b\u5efa'', created: ''\u5df2\u521b\u5efa'', updating: ''\u6b63\u5728\u66f4\u65b0'', updated: ''\u5df2\u66f4\u65b0'',',
            '      deleting: ''\u6b63\u5728\u5220\u9664'', deleted: ''\u5df2\u5220\u9664'', reading: ''\u6b63\u5728\u8bfb\u53d6'', writing: ''\u6b63\u5728\u5199\u5165'',',
            '      wrote: ''\u5df2\u5199\u5165'', listing: ''\u6b63\u5728\u5217\u51fa'', listed: ''\u5df2\u5217\u51fa'', checking: ''\u6b63\u5728\u68c0\u67e5'',',
            '      checked: ''\u5df2\u68c0\u67e5'', viewing: ''\u6b63\u5728\u67e5\u770b'', viewed: ''\u5df2\u67e5\u770b'',',
            '    };',
            '    const zhVerb = verbMap[verb.toLowerCase()] || verb;',
            '    const zhTarget = /^Task\s+Logs?$/i.test(target) ? ''\u4efb\u52a1\u65e5\u5fd7'' : target;',
            '    return `${zhVerb} ${zhTarget}`;',
            '  }],',
            '  [/^([\s\S]{3,}?)(?<!\b(?:as|is|are|was|were|be|been|not|never|when|until|before|after|get|got|almost|completely|nearly|just|already))\s+finished$/i, ''$1 \u5df2\u5b8c\u6210''],'
        ) -join "`n")
        $js = Replace-FirstMatch -Text $js -Variants @(
            @{ Target = '  const dynamicPatterns = ['; Replacement = "  const dynamicPatterns = [`n" + (Add-LineIndent -Text $dynEntries -Indent '  ') },
            @{ Target = "`nconst dynamicPatterns = ["; Replacement = "`nconst dynamicPatterns = [`n" + $dynEntries }
        ) -Label 'dynamicPatterns_time'

        $agoAnchorCore = Resolve-OverlayUnicode (@(
            '[/(\d+)\s*minutes?\s*ago\b/gi, ''$1 \u5206\u949f\u524d''],',
            '[/(\d+)\s*hours?\s*ago\b/gi, ''$1 \u5c0f\u65f6\u524d''],',
            '[/(\d+)\s*days?\s*ago\b/gi, ''$1 \u5929\u524d''],',
            '[/(\d+)\s*weeks?\s*ago\b/gi, ''$1 \u5468\u524d''],',
            '[/(\d+)\s*months?\s*ago\b/gi, ''$1 \u4e2a\u6708\u524d''],',
            '[/(\d+)\s*years?\s*ago\b/gi, ''$1 \u5e74\u524d''],'
        ) -join "`n")
        $agoCompactCore = Resolve-OverlayUnicode (@(
            '[/(\d+)\s*minutes?\s*ago\b/gi, ''$1\u5206\u949f\u524d''],',
            '[/(\d+)\s*hours?\s*ago\b/gi, ''$1\u5c0f\u65f6\u524d''],',
            '[/(\d+)\s*days?\s*ago\b/gi, ''$1\u5929\u524d''],',
            '[/(\d+)\s*weeks?\s*ago\b/gi, ''$1\u5468\u524d''],',
            '[/(\d+)\s*months?\s*ago\b/gi, ''$1\u4e2a\u6708\u524d''],',
            '[/(\d+)\s*years?\s*ago\b/gi, ''$1\u5e74\u524d''],'
        ) -join "`n")
        $js = Replace-FirstMatch -Text $js -Variants @(
            @{ Target = (Add-LineIndent -Text $agoAnchorCore -Indent '    '); Replacement = (Add-LineIndent -Text $agoCompactCore -Indent '    ') },
            @{ Target = (Add-LineIndent -Text $agoAnchorCore -Indent '  ');   Replacement = (Add-LineIndent -Text $agoCompactCore -Indent '  ') }
        ) -Label 'existing_ago'

        $greetingOldAnchor = Resolve-OverlayUnicode (@(
            '    const greeting = trimmed.match(/^Hi ([\s\S]+?), what can we get done today\?$/);',
            '    if (greeting) return value.replace(trimmed, () => `\u4f60\u597d\uff0c${greeting[1]}\uff0c\u4eca\u5929\u60f3\u5b8c\u6210\u4ec0\u4e48\uff1f`);',
            '    if (/^\u4f60\u597d\uff0c[\s\S]+\uff0c\u4eca\u5929\u60f3\u5b8c\u6210\u4ec0\u4e48\uff1f$/.test(trimmed)) return value;'
        ) -join "`n")
        $greetingNewAnchor = Resolve-OverlayUnicode (@(
            '  const greeting = trimmed.match(/^Hi ([\s\S]+?), what can we get done today\?$/);',
            '  if (greeting) return value.replace(trimmed, () => `\u4f60\u597d\uff0c${greeting[1]}\uff0c\u4eca\u5929\u60f3\u5b8c\u6210\u4ec0\u4e48\uff1f`);',
            '  const greetingBuild = trimmed.match(/^Hey ([\s\S]+?), what should we build today\?$/);',
            '  if (greetingBuild) return value.replace(trimmed, () => `\u55e8\uff0c${greetingBuild[1]}\uff0c\u4eca\u5929\u60f3\u6784\u5efa\u4ec0\u4e48\uff1f`);',
            '  const greetingNext = trimmed.match(/^Good to see you, ([\s\S]+?)\. What''s next\?$/);',
            '  if (greetingNext) return value.replace(trimmed, () => `\u5f88\u9ad8\u5174\u89c1\u5230\u4f60\uff0c${greetingNext[1]}\u3002\u63a5\u4e0b\u6765\u505a\u4ec0\u4e48\uff1f`);',
            '  const greetingBack = trimmed.match(/^Welcome back, ([\s\S]+?)\. Where should we pick up\?$/);',
            '  if (greetingBack) return value.replace(trimmed, () => `\u6b22\u8fce\u56de\u6765\uff0c${greetingBack[1]}\u3002\u6211\u4eec\u4ece\u54ea\u91cc\u7ee7\u7eed\uff1f`);',
            '  if (/^(?:\u4f60\u597d\uff0c[\s\S]+\uff0c\u4eca\u5929\u60f3\u5b8c\u6210\u4ec0\u4e48\uff1f|\u55e8\uff0c[\s\S]+\uff0c\u4eca\u5929\u60f3\u6784\u5efa\u4ec0\u4e48\uff1f|\u5f88\u9ad8\u5174\u89c1\u5230\u4f60\uff0c[\s\S]+\u3002\u63a5\u4e0b\u6765\u505a\u4ec0\u4e48\uff1f|\u6b22\u8fce\u56de\u6765\uff0c[\s\S]+\u3002\u6211\u4eec\u4ece\u54ea\u91cc\u7ee7\u7eed\uff1f)$/.test(trimmed)) return value;'
        ) -join "`n")
        $greetingPatchedCore = Resolve-OverlayUnicode (@(
            'const greeting = trimmed.match(/^Hi ([\s\S]+?), what can we get done today\?$/);',
            'if (greeting) return value.replace(trimmed, () => `\u4f60\u597d\uff0c${greeting[1]}\uff0c\u4eca\u5929\u60f3\u5b8c\u6210\u4ec0\u4e48\uff1f`);',
            'if (trimmed === ''Hey there, what should we build today?'') return value.replace(trimmed, ''\u4f60\u597d\uff0c\u4eca\u5929\u60f3\u6784\u5efa\u4ec0\u4e48\uff1f'');',
            'const heyNamed = trimmed.match(/^Hey ([\s\S]+?), what should we build today\?$/);',
            'if (heyNamed && heyNamed[1].toLowerCase() !== ''there'') return value.replace(trimmed, () => `\u4f60\u597d\uff0c${heyNamed[1]}\uff0c\u4eca\u5929\u60f3\u6784\u5efa\u4ec0\u4e48\uff1f`);',
            'if (trimmed === ''Welcome back. Where should we pick up?'') return value.replace(trimmed, ''\u6b22\u8fce\u56de\u6765\uff0c\u6211\u4eec\u4ece\u54ea\u91cc\u7ee7\u7eed\uff1f'');',
            'const welcomeNamed = trimmed.match(/^Welcome back, ([\s\S]+?)\. Where should we pick up\?$/);',
            'if (welcomeNamed) return value.replace(trimmed, () => `\u6b22\u8fce\u56de\u6765\uff0c${welcomeNamed[1]}\uff0c\u6211\u4eec\u4ece\u54ea\u91cc\u7ee7\u7eed\uff1f`);',
            'if (trimmed === "Good to see you. What''s next?") return value.replace(trimmed, ''\u5f88\u9ad8\u5174\u89c1\u5230\u4f60\uff0c\u63a5\u4e0b\u6765\u505a\u4ec0\u4e48\uff1f'');',
            'const goodSeeNamed = trimmed.match(/^Good to see you, ([\s\S]+?)\. What''s next\?$/);',
            'if (goodSeeNamed) return value.replace(trimmed, () => `\u5f88\u9ad8\u5174\u89c1\u5230\u4f60\uff0c${goodSeeNamed[1]}\uff0c\u63a5\u4e0b\u6765\u505a\u4ec0\u4e48\uff1f`);',
            'if (/^(?:\u4f60\u597d(?:\uff0c[\s\S]+)?\uff0c\u4eca\u5929\u60f3(?:\u5b8c\u6210|\u6784\u5efa)\u4ec0\u4e48\uff1f|\u55e8\uff0c[\s\S]+\uff0c\u4eca\u5929\u60f3\u6784\u5efa\u4ec0\u4e48\uff1f|\u6b22\u8fce\u56de\u6765(?:\uff0c[\s\S]+)?[\uff0c\u3002]\u6211\u4eec\u4ece\u54ea\u91cc\u7ee7\u7eed\uff1f|\u5f88\u9ad8\u5174\u89c1\u5230\u4f60(?:\uff0c[\s\S]+)?[\uff0c\u3002]\u63a5\u4e0b\u6765\u505a\u4ec0\u4e48\uff1f)$/.test(trimmed)) return value;'
        ) -join "`n")
        $js = Replace-FirstMatch -Text $js -Variants @(
            @{ Target = $greetingOldAnchor; Replacement = (Add-LineIndent -Text $greetingPatchedCore -Indent '    ') },
            @{ Target = $greetingNewAnchor; Replacement = (Add-LineIndent -Text $greetingPatchedCore -Indent '  ') }
        ) -Label 'home_greetings'

        $js = Replace-FirstMatch -Text $js -Variants @(
            @{
                Target = 'const historyItem = element.closest(''[data-testid="conversation-row-sidebar"], [data-cascade-id], '
                Replacement = 'const historyItem = element.closest(''[data-testid^="conversation-row-"], [data-testid="side-question-row"], [data-testid="subagent-node"], '
            },
            @{
                Target = 'const historyItem = element.closest(''[data-testid="conversation-row-sidebar"], [data-cascade-id]:not([data-testid="conversation-view"]), '
                Replacement = 'const historyItem = element.closest(''[data-testid^="conversation-row-"], [data-testid="side-question-row"], [data-testid="subagent-node"], [data-cascade-id]:not([data-testid="conversation-view"]), '
            }
        ) -Label 'historyItem_selector'

        $userSkipAnchorCore = Resolve-OverlayUnicode (@(
            '// \u8df3\u8fc7\u7528\u6237\u8f93\u5165',
            'if (element.closest(''[data-testid="user-input-step"], [aria-label="User message"], [aria-label="\u7528\u6237\u6d88\u606f"]'')) {',
            '  return true;',
            '}'
        ) -join "`n")
        $userSkipPatchedCore = Resolve-OverlayUnicode (@(
            '// \u8df3\u8fc7\u7528\u6237\u8f93\u5165\u6c14\u6ce1\u6b63\u6587\uff08\u4fdd\u7559 user-message-actions \u65f6\u95f4\u6233\u4e0e\u64cd\u4f5c\u6309\u94ae\uff09',
            'if (element.closest(''[data-testid="user-message-bubble"], [data-testid="user-message-content"], .agy-user-bubble, .agy-user-bubble-frame'')) {',
            '  return true;',
            '}'
        ) -join "`n")
        $userSkip236AnchorCore = Resolve-OverlayUnicode (@(
            '// \u8df3\u8fc7\u7528\u6237\u8f93\u5165',
            'if (element.closest(''[data-testid="user-input-step"], [data-testid="side-question-followup-user"], [aria-label="User message"], [aria-label="\u7528\u6237\u6d88\u606f"]'')) {',
            '  return true;',
            '}'
        ) -join "`n")
        $userSkip236PatchedCore = Resolve-OverlayUnicode (@(
            '// \u8df3\u8fc7\u7528\u6237\u8f93\u5165\u6c14\u6ce1\u6b63\u6587\u4e0e\u4fa7\u8fb9\u8ffd\u95ee\u7528\u6237\u8f93\u5165\uff08\u4fdd\u7559 user-message-actions \u65f6\u95f4\u6233\u4e0e\u64cd\u4f5c\u6309\u94ae\uff09',
            'if (element.closest(''[data-testid="user-message-bubble"], [data-testid="user-message-content"], [data-testid="side-question-followup-user"], .agy-user-bubble, .agy-user-bubble-frame'')) {',
            '  return true;',
            '}'
        ) -join "`n")
        $js = Replace-FirstMatch -Text $js -Variants @(
            @{ Target = (Add-LineIndent -Text $userSkipAnchorCore -Indent '    '); Replacement = (Add-LineIndent -Text $userSkipPatchedCore -Indent '    ') },
            @{ Target = (Add-LineIndent -Text $userSkipAnchorCore -Indent '  ');   Replacement = (Add-LineIndent -Text $userSkipPatchedCore -Indent '  ') },
            @{ Target = (Add-LineIndent -Text $userSkip236AnchorCore -Indent '    '); Replacement = (Add-LineIndent -Text $userSkip236PatchedCore -Indent '    ') },
            @{ Target = (Add-LineIndent -Text $userSkip236AnchorCore -Indent '  ');   Replacement = (Add-LineIndent -Text $userSkip236PatchedCore -Indent '  ') }
        ) -Label 'user_input_skip'

        $agentRespAnchorCore = Resolve-OverlayUnicode (@(
            '// \u8df3\u8fc7\u56de\u590d\u6b63\u6587\uff08\u4fdd\u7559\u63a7\u4ef6\u3001\u6298\u53e0\u6b65\u9aa4\u680f\u3001\u53d8\u66f4\u6982\u89c8\u4e0e\u7cfb\u7edf\u63d0\u793a\u5361\u7247\uff09',
            'const agentResponse = element.closest(''[aria-label="Agent response"], [aria-label="\u667a\u80fd\u4f53\u56de\u590d"]'');',
            'if (agentResponse) {',
            '  if (node.nodeType === Node.ELEMENT_NODE && element === agentResponse) return false;',
            '  const isInteractive = element.closest(''button, [role="button"], [class*="action"], [class*="button-container"], [data-testid="cleared-step-notice"], .files-changed-header'');'
        ) -join "`n")
        $agentRespPatchedCore = Resolve-OverlayUnicode (@(
            'const userStep = element.closest(''[data-testid="user-input-step"], [aria-label="User message"], [aria-label="\u7528\u6237\u6d88\u606f"]'');',
            'if (userStep) {',
            '  if (node.nodeType === Node.ELEMENT_NODE && element === userStep) return false;',
            '  if (!element.closest(''[data-testid="user-message-actions"], [data-screenshot-volatile], button, [role="button"]'')) return true;',
            '}',
            '',
            '// \u8df3\u8fc7\u56de\u590d\u6b63\u6587\uff08\u4fdd\u7559\u63a7\u4ef6\u3001\u6298\u53e0\u6b65\u9aa4\u680f\u3001\u6d88\u606f\u64cd\u4f5c\u65f6\u95f4\u680f\u3001\u53d8\u66f4\u6982\u89c8\u4e0e\u7cfb\u7edf\u63d0\u793a\u5361\u7247\uff09',
            'const agentResponse = element.closest(''[aria-label="Agent response"], [aria-label="\u667a\u80fd\u4f53\u56de\u590d"]'');',
            'if (agentResponse) {',
            '  if (node.nodeType === Node.ELEMENT_NODE && element === agentResponse) return false;',
            '  const isInteractive = element.closest(''button, [role="button"], [class*="action"], [class*="button-container"], [data-testid="cascade-system-message-toolbar"], [data-screenshot-volatile], [data-testid="cleared-step-notice"], .files-changed-header'');'
        ) -join "`n")
        $js = Replace-FirstMatch -Text $js -Variants @(
            @{ Target = (Add-LineIndent -Text $agentRespAnchorCore -Indent '    '); Replacement = (Add-LineIndent -Text $agentRespPatchedCore -Indent '    ') },
            @{ Target = (Add-LineIndent -Text $agentRespAnchorCore -Indent '  ');   Replacement = (Add-LineIndent -Text $agentRespPatchedCore -Indent '  ') }
        ) -Label 'agent_resp_skip'

        $js = Replace-FirstMatch -Text $js -Variants @(
            @{ Target = "`n    '.antigravity-welcome-container',"; Replacement = "`n    '.antigravity-welcome-container',`n    '[data-testid=""home-greeting""]'," },
            @{ Target = "`n  '.antigravity-welcome-container',";   Replacement = "`n  '.antigravity-welcome-container',`n  '[data-testid=""home-greeting""]'," }
        ) -Label 'container_sel'

        $js = Replace-Once -Text $js -Target "    flushScheduler?.cancel();`n    restoreIdeNlsMessages();`n    removePreferenceSync?.();" -Replacement "    flushScheduler?.cancel();`n    clearTitleTimers();`n    restoreIdeNlsMessages();`n    removePreferenceSync?.();" -Label 'cleanup_timers'

        $restoreTarget = @(
            '  function restoreOriginals() {',
            '    const walker = document.createTreeWalker(document, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT);',
            '    for (let node = walker.nextNode(); node; node = walker.nextNode()) {',
            '      restoreTrackedNode(node);',
            '    }',
            '  }'
        ) -join "`n"
        $restorePatched = @(
            '  function restoreOriginals() {',
            '    const walker = document.createTreeWalker(document, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT);',
            '    for (let node = walker.nextNode(); node; node = walker.nextNode()) {',
            '      restoreTrackedNode(node);',
            '    }',
            '    restoreDocTitle();',
            '  }'
        ) -join "`n"
        $js = Replace-Once -Text $js -Target $restoreTarget -Replacement $restorePatched -Label 'restoreOriginals'

        $titleModule = @(
            '  const TITLE_MAP_KEY = "antigravityHansAutoTitleMap";',
            '  const CJK_CHAR_RE = /[\u3400-\u9fff\uf900-\ufaff\u3040-\u30ff\uac00-\ud7af]/;',
            '  let originalDocTitle = null;',
            '  let titleResyncTimers = [];',
            '  function clearTitleTimers() { for (const tid of titleResyncTimers) clearTimeout(tid); titleResyncTimers = []; }',
            '  function restoreDocTitle() { if (originalDocTitle !== null && typeof document !== "undefined") { document.title = originalDocTitle; originalDocTitle = null; } }',
            '  function loadAutoTitleMap() { try { const r = loadPref(TITLE_MAP_KEY); if (!r) return {}; const p = JSON.parse(r); return p && typeof p === "object" && !Array.isArray(p) ? p : {}; } catch (_e) { return {}; } }',
            '  function saveAutoTitleMap(m) { try { const es = Object.entries(m); savePref(TITLE_MAP_KEY, JSON.stringify(es.length > 200 ? Object.fromEntries(es.slice(-200)) : m)); } catch (_e) {} }',
            '  function isAutoEnglishTitle(raw) {',
            '    const s = (raw || "").trim();',
            '    if (s.length < 4 || s.length > 80 || CJK_CHAR_RE.test(s)) return false;',
            '    if (/[/\\]|https?:|^[~.]/i.test(s) || /\.[a-z0-9]{1,5}$/i.test(s)) return false;',
            '    if (!/^[A-Za-z0-9][A-Za-z0-9\s:&+\-/''"(),.?]{2,}$/.test(s)) return false;',
            '    const aw = s.split(/\s+/).filter(Boolean).filter((w) => /[A-Za-z]/.test(w));',
            '    if (aw.length < 2) return false;',
            '    const titled = aw.filter((w) => /^[A-Z]/.test(w) || /^(?:of|to|in|on|at|for|by|with|and|or|vs|the|a|an)$/i.test(w));',
            '    return titled.length / aw.length >= 0.7 && /^[A-Z0-9]/.test(aw[0]);',
            '  }',
            '  function extractFirstChineseUserPrompt(convoView) {',
            '    const step = convoView.querySelector(''[data-testid="user-input-step"]'') || convoView.querySelector(''[aria-label="User message"], [aria-label="\u7528\u6237\u6d88\u606f"]'');',
            '    if (!step) return "";',
            '    const skip = new Set(step.querySelectorAll(''button, [role="button"], [data-testid="queued-decorators"], [data-testid="user-message-actions"], [data-screenshot-volatile], time, svg''));',
            '    const parts = [];',
            '    const w = document.createTreeWalker(step, NodeFilter.SHOW_TEXT);',
            '    for (let n = w.nextNode(); n; n = w.nextNode()) {',
            '      let cur = n.parentElement, ign = false;',
            '      while (cur && cur !== step) { if (skip.has(cur)) { ign = true; break; } cur = cur.parentElement; }',
            '      if (ign) continue;',
            '      const t = (n.nodeValue || "").trim();',
            '      if (t && !/^\d+\s*(?:s|m|h|d)?\s*ago$/i.test(t) && t !== "You") parts.push(t);',
            '    }',
            '    const text = parts.join(" ").replace(/\s+/g, " ").trim();',
            '    const hm = text.match(/[\u4e00-\u9fff]/g);',
            '    return hm && hm.length >= 2 ? text : "";',
            '  }',
            '  function trimDirectiveTail(cs) {',
            '    const tr = /^(?:\u7ed9\u4e2a?.*\u4f8b\u5b50|\u4e3e\u4e2a?\u4f8b\u5b50|\u9644\u5e26?\u4f8b\u5b50|\u7b80\u77ed\u8bf4\u660e|\u7b80\u660e\u56de\u7b54|\u8bf4\u6e05.*|\u4e24\u4e09\u53e5\u8bdd.*|\u7528.*\u56de\u7b54|\u8bf7\u7b80\u8ff0|\u8c22\u8c22|\u611f\u8c22).*$/;',
            '    const f = cs.filter((c, i) => !(i > 0 && i === cs.length - 1 && tr.test(c)));',
            '    return f.length > 0 ? f : cs;',
            '  }',
            '  function deriveZhTitleFromPrompt(promptText) {',
            '    const clean = (promptText || "").replace(/\s+/g, " ").trim();',
            '    const ss = clean.split(/[\u3002\uff01\uff1f!?\n\uff1b;]+/).map((s) => s.trim()).filter(Boolean);',
            '    let first = ss.find((s) => (s.match(/[\u4e00-\u9fff]/g) || []).length >= 2) || "";',
            '    if (!first) return "";',
            '    const pfx = /^(?:\u4f60\u597d|\u60a8\u597d|\u8bf7\u95ee|\u9ebb\u70e6(?:\u4f60|\u60a8)?|\u8bf7(?:\u5e2e\u6211)?|\u5e2e\u6211|\u80fd\u4e0d\u80fd|\u53ef\u4ee5(?:\u5e2e\u6211)?|\u80fd\u5426|\u987a\u4fbf|\u6211\u60f3(?:\u95ee\u4e00\u4e0b|\u77e5\u9053|\u4e86\u89e3)?|\u60f3\u95ee(?:\u4e00\u4e0b)?|\u7528[\u4e00\u4e8c\u4e09\u56db\u4e94\u516d\u4e03\u516b\u4e5d\u5341\u4e24\u51e0\d]+\u4e2a?[\u53e5\u5b57\u6bb5\u8bdd]+(?:\u6765\u8bb2|\u6765\u8bf4|\u8bf4|\u8bf4\u660e|\u89e3\u91ca|\u6982\u62ec)?|\u7b80\u77ed\u5730?|\u7b80\u5355\u5730?|\u901a\u4fd7\u5730?|\u8be6\u7ec6\u5730?|\u5feb\u901f\u5730?)[\uff0c,\s]*/;',
            '    const vrb = /^(?:\u8bb2\u4e00\u8bb2|\u8bb2\u8bb2|\u8bf4\u4e00\u8bf4|\u8bf4\u8bf4|\u89e3\u91ca\u4e00\u4e0b|\u89e3\u91ca\u4e0b|\u89e3\u91ca|\u4ecb\u7ecd\u4e00\u4e0b|\u4ecb\u7ecd\u4e0b|\u4ecb\u7ecd|\u804a\u4e00\u804a|\u804a\u804a|\u544a\u8bc9\u6211|\u56de\u7b54\u4e00\u4e0b|\u56de\u7b54|\u603b\u7ed3\u4e00\u4e0b|\u603b\u7ed3|\u5206\u6790\u4e00\u4e0b|\u5206\u6790|\u7ed9\u4e2a|\u5199\u4e00\u4e0b|\u5199\u4e2a)[\uff0c,\s]*/;',
            '    for (let i = 0; i < 4; i++) { const n = first.replace(pfx, "").trim(); if (n === first) break; if ((n.match(/[\u4e00-\u9fff]/g) || []).length >= 2) first = n; }',
            '    const av = first.replace(vrb, "").trim();',
            '    if ((av.match(/[\u4e00-\u9fff]/g) || []).length >= 2) first = av;',
            '    first = first.replace(/[\uff0c,\uff1a:\s]+$/, "");',
            '    if (first.length <= 18) return first;',
            '    let cs = trimDirectiveTail(first.split(/[\uff0c,]+/).map((c) => c.trim()).filter(Boolean));',
            '    const joined = cs.join("\uff0c");',
            '    if (joined.length <= 18) return joined;',
            '    const focus = /[\u51e0\u591a\u5c11\u600e\u4e3a\u4f55\u54ea\u8c01\u5417]/;',
            '    const fc = cs.find((c, idx) => idx > 0 && focus.test(c) && c.length >= 6 && c.length <= 18);',
            '    if (fc) return fc;',
            '    if (cs[0] && cs[0].length >= 6 && cs[0].length <= 18) return cs[0];',
            '    const cand = joined.slice(0, 17).replace(/[\uff0c,\u3001\s]+$/, "");',
            '    return cand ? cand + "\u2026" : "";',
            '  }',
            '  function findFirstVisibleTextNode(root) {',
            '    if (!root) return null;',
            '    const w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);',
            '    for (let n = w.nextNode(); n; n = w.nextNode()) { if (!n.parentElement?.closest?.("svg, input, textarea, [data-agy-hans-ui]") && (n.nodeValue || "").trim()) return n; }',
            '    return null;',
            '  }',
            '  function scheduleTitleResync() {',
            '    if (cancelled || lang !== "zh" || titleResyncTimers.length > 0) return;',
            '    titleResyncTimers.push(setTimeout(() => { if (!cancelled && lang === "zh") syncChineseConversationTitles(true); }, 1200));',
            '    titleResyncTimers.push(setTimeout(() => { titleResyncTimers = []; if (!cancelled && lang === "zh") syncChineseConversationTitles(true); }, 3200));',
            '  }',
            '  function syncChineseConversationTitles(fromTimer = false) {',
            '    if (cancelled || lang !== "zh" || typeof document === "undefined") return;',
            '    const titleMap = loadAutoTitleMap();',
            '    let mapChanged = false;',
            '    const convoView = document.querySelector(''[data-testid="conversation-view"], [data-testid="side-question-tab-conversation"]'');',
            '    const promptText = convoView ? extractFirstChineseUserPrompt(convoView) : "";',
            '    const segments = Array.from(document.querySelectorAll(''[data-testid="breadcrumb-segment"]''));',
            '    if (convoView && segments.length > 0) {',
            '      const seg = segments[segments.length - 1];',
            '      if (!seg.querySelector("input, textarea") && (seg.hasAttribute("data-tooltip-id") || segments.length >= 2 || promptText)) {',
            '        const tn = findFirstVisibleTextNode(seg);',
            '        if (tn) {',
            '          const tr = originals.texts.get(tn);',
            '          const orig = (tr ? tr.orig : (tn.nodeValue || "")).trim();',
            '          if (isAutoEnglishTitle(orig)) {',
            '            let zh = titleMap[orig];',
            '            if (!zh && promptText) { zh = deriveZhTitleFromPrompt(promptText); if (zh) { titleMap[orig] = zh; mapChanged = true; } }',
            '            if (zh) {',
            '              if (tn.nodeValue !== zh) writeText(tn, zh);',
            '              tn.__zh_patched = true;',
            '              if (document.title && document.title.includes(orig)) {',
            '                if (originalDocTitle === null) originalDocTitle = document.title;',
            '                const nt = originalDocTitle.includes(orig) ? originalDocTitle.replace(orig, () => zh) : document.title.replace(orig, () => zh);',
            '                if (document.title !== nt) document.title = nt;',
            '              }',
            '            }',
            '          }',
            '        }',
            '      }',
            '    }',
            '    if (!fromTimer && promptText) {',
            '      const lastSeg = segments[segments.length - 1];',
            '      const ctn = lastSeg ? findFirstVisibleTextNode(lastSeg) : null;',
            '      const cv = ctn ? (ctn.nodeValue || "").trim() : "";',
            '      if (!cv || !CJK_CHAR_RE.test(cv)) scheduleTitleResync();',
            '    }',
            '    for (const row of document.querySelectorAll(''[data-testid^="conversation-row-"], [data-testid="side-question-row"]'')) {',
            '      const w = document.createTreeWalker(row, NodeFilter.SHOW_TEXT);',
            '      for (let n = w.nextNode(); n; n = w.nextNode()) {',
            '        if (n.parentElement?.closest?.("svg, button")) continue;',
            '        const tr = originals.texts.get(n);',
            '        const raw = tr ? tr.orig : (n.nodeValue || "");',
            '        const t = raw.trim();',
            '        const mp = t ? titleMap[t] : "";',
            '        if (mp) { const nv = raw.replace(t, () => mp); if (n.nodeValue !== nv) writeText(n, nv); n.__zh_patched = true; }',
            '      }',
            '    }',
            '    if (mapChanged) saveAutoTitleMap(titleMap);',
            '  }',
            '  function applyChinese(resetMarks) {'
        ) -join "`n"
        $js = Replace-Once -Text $js -Target '  function applyChinese(resetMarks) {' -Replacement $titleModule -Label 'title_module'

        $js = Replace-Once -Text $js -Target "    translateNode(document);`n  }" -Replacement "    translateNode(document);`n    syncChineseConversationTitles();`n  }" -Label 'applyChinese_end'

        $flushTarget = @(
            '    flushScheduler = createFlushScheduler((batchNodes, batchElements) => {',
            "      if (cancelled || lang !== 'zh') return;",
            '      for (const node of batchNodes) translateNode(node);',
            '      for (const element of batchElements) translateElement(element);',
            '    });'
        ) -join "`n"
        $flushPatched = @(
            '    flushScheduler = createFlushScheduler((batchNodes, batchElements) => {',
            "      if (cancelled || lang !== 'zh') return;",
            '      for (const node of batchNodes) translateNode(node);',
            '      for (const element of batchElements) translateElement(element);',
            '      syncChineseConversationTitles();',
            '    });'
        ) -join "`n"
        $js = Replace-Once -Text $js -Target $flushTarget -Replacement $flushPatched -Label 'flushScheduler'
    } catch {
        Write-Warning "Enhanced overlay anchor mismatch ($($_.Exception.Message)); falling back to base overlay."
        $js = $rawJs.Replace("`r`n", "`n")
    }

    $finalContent = $headerComment + "`n" + $js.TrimEnd() + "`n"
    $overlayDir = Split-Path -Parent $OverlayJs
    New-Item -ItemType Directory -Force -Path $overlayDir | Out-Null
    $tmpOverlay = Join-Path $overlayDir ('.antigravity-hans-overlay.' + [System.Guid]::NewGuid().ToString('N') + '.tmp')
    [System.IO.File]::WriteAllText($tmpOverlay, $finalContent, [System.Text.UTF8Encoding]::new($false))
    Move-Item -Force $tmpOverlay $OverlayJs
    return $true
}

