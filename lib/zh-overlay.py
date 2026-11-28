import hashlib
import os
import sys
import tempfile

base_path, overlay_path, overlay_ver, force_flag = sys.argv[1:5]
force = force_flag == "true"

with open(base_path, "r", encoding="utf-8") as f:
    raw_js = f.read()

base_sha256 = hashlib.sha256(raw_js.encode("utf-8")).hexdigest()[:16]
header_comment = f"// antigravity-zh-launcher overlay: {overlay_ver}; base_sha256={base_sha256}"

if not force and os.path.isfile(overlay_path):
    try:
        with open(overlay_path, "r", encoding="utf-8") as ef:
            first_line = ef.readline().rstrip("\r\n")
        if first_line == header_comment:
            sys.exit(0)
    except Exception:
        pass

js = raw_js.replace("\r\n", "\n")


class AnchorError(RuntimeError):
    pass


def indent_lines(text, prefix):
    if not prefix:
        return text
    return "\n".join(prefix + line if line else "" for line in text.split("\n"))


def replace_first_match(text, variants, label):
    counts = [text.count(target) for target, _ in variants]
    if any(count > 1 for count in counts):
        raise AnchorError(f"锚点匹配异常 ({label}): counts={counts}")
    hits = [(target, replacement) for (target, replacement), count in zip(variants, counts) if count == 1]
    if len(hits) != 1:
        raise AnchorError(f"锚点匹配异常 ({label}): counts={counts}")
    target, replacement = hits[0]
    return text.replace(target, replacement, 1)


def replace_once(text, target, replacement, label):
    return replace_first_match(text, [(target, replacement)], label)


try:
    # 1. 补全输入框提示语、运行链路动作词及常见变体词条
    phrases_anchor = "  const phrases = new Map(["
    phrases_addon = """  const phrases = new Map([
    ["Ask anything, @ to mention, / for actions", "想问什么都可以，@ 引用，/ 执行动作"],
    ["Ask anything, @ to mention", "想问什么都可以，@ 引用"],
    ["Message subagent, @ to mention, / for actions", "向子智能体发消息，@ 引用，/ 执行动作"],
    ["Message subagent, @ to mention", "向子智能体发消息，@ 引用"],
    ["Listening. Ask anything.", "正在聆听，想问什么都可以。"],
    ["Analyzed", "已分析"],
    ["Analyzing", "正在分析"],
    ["Editing", "正在编辑"],
    ["Creating", "正在创建"],
    ["Created", "已创建"],
    ["Updating", "正在更新"],
    ["Updated", "已更新"],
    ["Deleting", "正在删除"],
    ["Reading", "正在读取"],
    ["Writing", "正在写入"],
    ["Wrote", "已写入"],
    ["Listing", "正在列出"],
    ["Listed", "已列出"],
    ["Checking", "正在检查"],
    ["Checked", "已检查"],
    ["Viewing", "正在查看"],
    ["Viewed", "已查看"],
    ["Exploring", "正在探索"],
    ["Invoking", "正在调用"],
    ["Invoked", "已调用"],
    ["Started", "已开始"],
    ["Starting", "正在启动"],
    ["Task Log", "任务日志"],
    ["Finished", "已完成"],
    ["finished", "已完成"],"""
    js = replace_once(js, phrases_anchor, phrases_addon, "phrases")

    # 2. 补充简短相对时间及单节点工具步骤行规则（8m ago / Editing foo.js / ... finished）
    dyn_entries = """  [/^(\\d+)\\s*s\\s+ago$/i, '$1秒前'],
  [/^(\\d+)\\s*m\\s+ago$/i, '$1分钟前'],
  [/^(\\d+)\\s*h\\s+ago$/i, '$1小时前'],
  [/^(\\d+)\\s*d\\s+ago$/i, '$1天前'],
  [/^(\\d+)\\s*w\\s+ago$/i, '$1周前'],
  [/^(\\d+)\\s*mo\\s+ago$/i, '$1个月前'],
  [/^(\\d+)\\s*y\\s+ago$/i, '$1年前'],
  [/^(?:Just now|now)$/i, '刚刚'],
  [/^(Analyzed|Analyzing|Editing|Edited|Creating|Created|Updating|Updated|Deleting|Deleted|Reading|Writing|Wrote|Listing|Listed|Checking|Checked|Viewing|Viewed)\\s+(Task\\s+Logs?|[^\\r\\n]+?(?:\\.[A-Za-z0-9]{1,8}(?:\\s+#L\\d+(?:-\\d+)?)?|\\s+#L\\d+(?:-\\d+)?)|[^\\s\\r\\n]+)$/i, (_m, verb, target) => {
    const verbMap = {
      analyzed: '已分析', analyzing: '正在分析', editing: '正在编辑', edited: '已编辑',
      creating: '正在创建', created: '已创建', updating: '正在更新', updated: '已更新',
      deleting: '正在删除', deleted: '已删除', reading: '正在读取', writing: '正在写入',
      wrote: '已写入', listing: '正在列出', listed: '已列出', checking: '正在检查',
      checked: '已检查', viewing: '正在查看', viewed: '已查看',
    };
    const zhVerb = verbMap[verb.toLowerCase()] || verb;
    const zhTarget = /^Task\\s+Logs?$/i.test(target) ? '任务日志' : target;
    return `${zhVerb} ${zhTarget}`;
  }],
  [/^([\\s\\S]{3,}?)(?<!\\b(?:as|is|are|was|were|be|been|not|never|when|until|before|after|get|got|almost|completely|nearly|just|already))\\s+finished$/i, '$1 已完成'],"""
    js = replace_first_match(
        js,
        [
            ("  const dynamicPatterns = [", "  const dynamicPatterns = [\n" + indent_lines(dyn_entries, "  ")),
            ("\nconst dynamicPatterns = [", "\nconst dynamicPatterns = [\n" + dyn_entries),
        ],
        "dynamicPatterns_time",
    )

    # 2b. 对齐已有长英文相对时间规则为紧凑格式（8分钟前）
    ago_anchor_core = """[/(\\d+)\\s*minutes?\\s*ago\\b/gi, '$1 分钟前'],
[/(\\d+)\\s*hours?\\s*ago\\b/gi, '$1 小时前'],
[/(\\d+)\\s*days?\\s*ago\\b/gi, '$1 天前'],
[/(\\d+)\\s*weeks?\\s*ago\\b/gi, '$1 周前'],
[/(\\d+)\\s*months?\\s*ago\\b/gi, '$1 个月前'],
[/(\\d+)\\s*years?\\s*ago\\b/gi, '$1 年前'],"""
    ago_compact_core = """[/(\\d+)\\s*minutes?\\s*ago\\b/gi, '$1分钟前'],
[/(\\d+)\\s*hours?\\s*ago\\b/gi, '$1小时前'],
[/(\\d+)\\s*days?\\s*ago\\b/gi, '$1天前'],
[/(\\d+)\\s*weeks?\\s*ago\\b/gi, '$1周前'],
[/(\\d+)\\s*months?\\s*ago\\b/gi, '$1个月前'],
[/(\\d+)\\s*years?\\s*ago\\b/gi, '$1年前'],"""
    js = replace_first_match(
        js,
        [(indent_lines(ago_anchor_core, indent), indent_lines(ago_compact_core, indent)) for indent in ("    ", "  ")],
        "existing_ago",
    )

    # 2c. 扩展首页全量 6 种轮换动态欢迎语（Hey guo, what should we build today? 等）
    greeting_old_anchor = """    const greeting = trimmed.match(/^Hi ([\\s\\S]+?), what can we get done today\\?$/);
    if (greeting) return value.replace(trimmed, () => `你好，${greeting[1]}，今天想完成什么？`);
    if (/^你好，[\\s\\S]+，今天想完成什么？$/.test(trimmed)) return value;"""
    greeting_new_anchor = """  const greeting = trimmed.match(/^Hi ([\\s\\S]+?), what can we get done today\\?$/);
  if (greeting) return value.replace(trimmed, () => `你好，${greeting[1]}，今天想完成什么？`);
  const greetingBuild = trimmed.match(/^Hey ([\\s\\S]+?), what should we build today\\?$/);
  if (greetingBuild) return value.replace(trimmed, () => `嗨，${greetingBuild[1]}，今天想构建什么？`);
  const greetingNext = trimmed.match(/^Good to see you, ([\\s\\S]+?)\\. What's next\\?$/);
  if (greetingNext) return value.replace(trimmed, () => `很高兴见到你，${greetingNext[1]}。接下来做什么？`);
  const greetingBack = trimmed.match(/^Welcome back, ([\\s\\S]+?)\\. Where should we pick up\\?$/);
  if (greetingBack) return value.replace(trimmed, () => `欢迎回来，${greetingBack[1]}。我们从哪里继续？`);
  if (/^(?:你好，[\\s\\S]+，今天想完成什么？|嗨，[\\s\\S]+，今天想构建什么？|很高兴见到你，[\\s\\S]+。接下来做什么？|欢迎回来，[\\s\\S]+。我们从哪里继续？)$/.test(trimmed)) return value;"""
    greeting_patched_core = """const greeting = trimmed.match(/^Hi ([\\s\\S]+?), what can we get done today\\?$/);
if (greeting) return value.replace(trimmed, () => `你好，${greeting[1]}，今天想完成什么？`);
if (trimmed === 'Hey there, what should we build today?') return value.replace(trimmed, '你好，今天想构建什么？');
const heyNamed = trimmed.match(/^Hey ([\\s\\S]+?), what should we build today\\?$/);
if (heyNamed && heyNamed[1].toLowerCase() !== 'there') return value.replace(trimmed, () => `你好，${heyNamed[1]}，今天想构建什么？`);
if (trimmed === 'Welcome back. Where should we pick up?') return value.replace(trimmed, '欢迎回来，我们从哪里继续？');
const welcomeNamed = trimmed.match(/^Welcome back, ([\\s\\S]+?)\\. Where should we pick up\\?$/);
if (welcomeNamed) return value.replace(trimmed, () => `欢迎回来，${welcomeNamed[1]}，我们从哪里继续？`);
if (trimmed === "Good to see you. What's next?") return value.replace(trimmed, '很高兴见到你，接下来做什么？');
const goodSeeNamed = trimmed.match(/^Good to see you, ([\\s\\S]+?)\\. What's next\\?$/);
if (goodSeeNamed) return value.replace(trimmed, () => `很高兴见到你，${goodSeeNamed[1]}，接下来做什么？`);
if (/^(?:你好(?:，[\\s\\S]+)?，今天想(?:完成|构建)什么？|嗨，[\\s\\S]+，今天想构建什么？|欢迎回来(?:，[\\s\\S]+)?[，。]我们从哪里继续？|很高兴见到你(?:，[\\s\\S]+)?[，。]接下来做什么？)$/.test(trimmed)) return value;"""
    js = replace_first_match(
        js,
        [
            (greeting_old_anchor, indent_lines(greeting_patched_core, "    ")),
            (greeting_new_anchor, indent_lines(greeting_patched_core, "  ")),
        ],
        "home_greetings",
    )

    # 3. 修复 [data-cascade-id] 误判主对话视图，并放行消息时间戳与首页欢迎语容器
    js = replace_first_match(
        js,
        [
            (
                "const historyItem = element.closest('[data-testid=\"conversation-row-sidebar\"], [data-cascade-id], ",
                "const historyItem = element.closest('[data-testid^=\"conversation-row-\"], [data-testid=\"side-question-row\"], [data-testid=\"subagent-node\"], ",
            ),
            (
                "const historyItem = element.closest('[data-testid=\"conversation-row-sidebar\"], [data-cascade-id]:not([data-testid=\"conversation-view\"]), ",
                "const historyItem = element.closest('[data-testid^=\"conversation-row-\"], [data-testid=\"side-question-row\"], [data-testid=\"subagent-node\"], [data-cascade-id]:not([data-testid=\"conversation-view\"]), ",
            ),
        ],
        "historyItem_selector",
    )

    user_skip_anchor_core = """// 跳过用户输入
if (element.closest('[data-testid="user-input-step"], [aria-label="User message"], [aria-label="用户消息"]')) {
  return true;
}"""
    user_skip_patched_core = """// 跳过用户输入气泡正文（保留 user-message-actions 时间戳与操作按钮）
if (element.closest('[data-testid="user-message-bubble"], [data-testid="user-message-content"], .agy-user-bubble, .agy-user-bubble-frame')) {
  return true;
}"""
    user_skip_236_anchor_core = """// 跳过用户输入
if (element.closest('[data-testid="user-input-step"], [data-testid="side-question-followup-user"], [aria-label="User message"], [aria-label="用户消息"]')) {
  return true;
}"""
    user_skip_236_patched_core = """// 跳过用户输入气泡正文与侧边追问用户输入（保留 user-message-actions 时间戳与操作按钮）
if (element.closest('[data-testid="user-message-bubble"], [data-testid="user-message-content"], [data-testid="side-question-followup-user"], .agy-user-bubble, .agy-user-bubble-frame')) {
  return true;
}"""
    js = replace_first_match(
        js,
        [
            (indent_lines(user_skip_anchor_core, indent), indent_lines(user_skip_patched_core, indent))
            for indent in ("    ", "  ")
        ]
        + [
            (indent_lines(user_skip_236_anchor_core, indent), indent_lines(user_skip_236_patched_core, indent))
            for indent in ("    ", "  ")
        ],
        "user_input_skip",
    )

    agent_resp_anchor_core = """// 跳过回复正文（保留控件、折叠步骤栏、变更概览与系统提示卡片）
const agentResponse = element.closest('[aria-label="Agent response"], [aria-label="智能体回复"]');
if (agentResponse) {
  if (node.nodeType === Node.ELEMENT_NODE && element === agentResponse) return false;
  const isInteractive = element.closest('button, [role="button"], [class*="action"], [class*="button-container"], [data-testid="cleared-step-notice"], .files-changed-header');"""
    agent_resp_patched_core = """const userStep = element.closest('[data-testid="user-input-step"], [aria-label="User message"], [aria-label="用户消息"]');
if (userStep) {
  if (node.nodeType === Node.ELEMENT_NODE && element === userStep) return false;
  if (!element.closest('[data-testid="user-message-actions"], [data-screenshot-volatile], button, [role="button"]')) return true;
}

// 跳过回复正文（保留控件、折叠步骤栏、消息操作时间栏、变更概览与系统提示卡片）
const agentResponse = element.closest('[aria-label="Agent response"], [aria-label="智能体回复"]');
if (agentResponse) {
  if (node.nodeType === Node.ELEMENT_NODE && element === agentResponse) return false;
  const isInteractive = element.closest('button, [role="button"], [class*="action"], [class*="button-container"], [data-testid="cascade-system-message-toolbar"], [data-screenshot-volatile], [data-testid="cleared-step-notice"], .files-changed-header');"""
    js = replace_first_match(
        js,
        [(indent_lines(agent_resp_anchor_core, indent), indent_lines(agent_resp_patched_core, indent)) for indent in ("    ", "  ")],
        "agent_resp_skip",
    )

    js = replace_first_match(
        js,
        [
            (
                "\n" + indent + "'.antigravity-welcome-container',",
                "\n" + indent + "'.antigravity-welcome-container',\n" + indent + "'[data-testid=\"home-greeting\"]',",
            )
            for indent in ("    ", "  ")
        ],
        "container_sel",
    )

    # 4. 在 cleanup 中清理标题复检定时器
    cleanup_anchor = """    flushScheduler?.cancel();
    restoreIdeNlsMessages();
    removePreferenceSync?.();"""
    cleanup_patched = """    flushScheduler?.cancel();
    clearTitleTimers();
    restoreIdeNlsMessages();
    removePreferenceSync?.();"""
    js = replace_once(js, cleanup_anchor, cleanup_patched, "cleanup_timers")

    # 5. 在 restoreOriginals 末尾还原 document.title
    restore_anchor = """  function restoreOriginals() {
    const walker = document.createTreeWalker(document, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      restoreTrackedNode(node);
    }
  }"""
    restore_patched = """  function restoreOriginals() {
    const walker = document.createTreeWalker(document, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      restoreTrackedNode(node);
    }
    restoreDocTitle();
  }"""
    js = replace_once(js, restore_anchor, restore_patched, "restoreOriginals")

    # 6. 注入自动英文会话标题汉化与侧边栏同步模块
    title_module = r"""  const TITLE_MAP_KEY = 'antigravityHansAutoTitleMap';
  const CJK_CHAR_RE = /[\u3400-\u9fff\uf900-\ufaff\u3040-\u30ff\uac00-\ud7af]/;
  let originalDocTitle = null;
  let titleResyncTimers = [];

  function clearTitleTimers() {
    for (const tid of titleResyncTimers) clearTimeout(tid);
    titleResyncTimers = [];
  }

  function restoreDocTitle() {
    if (originalDocTitle !== null && typeof document !== 'undefined') {
      document.title = originalDocTitle;
      originalDocTitle = null;
    }
  }

  function loadAutoTitleMap() {
    try {
      const raw = loadPref(TITLE_MAP_KEY);
      if (!raw) return {};
      const parsed = JSON.parse(raw);
      return parsed && typeof parsed === 'object' && !Array.isArray(parsed) ? parsed : {};
    } catch (_e) {
      return {};
    }
  }

  function saveAutoTitleMap(map) {
    try {
      const entries = Object.entries(map);
      const trimmed = entries.length > 200 ? Object.fromEntries(entries.slice(-200)) : map;
      savePref(TITLE_MAP_KEY, JSON.stringify(trimmed));
    } catch (_e) { /* ignore */ }
  }

  function isAutoEnglishTitle(raw) {
    const s = (raw || '').trim();
    if (s.length < 4 || s.length > 80) return false;
    if (CJK_CHAR_RE.test(s)) return false;
    if (/[/\\]|https?:|^[~.]/i.test(s) || /\.[a-z0-9]{1,5}$/i.test(s)) return false;
    if (!/^[A-Za-z0-9][A-Za-z0-9\s:&+\-/'"(),.?]{2,}$/.test(s)) return false;
    const words = s.split(/\s+/).filter(Boolean);
    const alphaWords = words.filter((w) => /[A-Za-z]/.test(w));
    if (alphaWords.length < 2) return false;
    const titled = alphaWords.filter((w) => /^[A-Z]/.test(w) || /^(?:of|to|in|on|at|for|by|with|and|or|vs|the|a|an)$/i.test(w));
    return titled.length / alphaWords.length >= 0.7 && /^[A-Z0-9]/.test(alphaWords[0]);
  }

  function extractFirstChineseUserPrompt(convoView) {
    const step = convoView.querySelector('[data-testid="user-input-step"]') ||
      convoView.querySelector('[aria-label="User message"], [aria-label="用户消息"]');
    if (!step) return '';
    const skipNodes = new Set(step.querySelectorAll('button, [role="button"], [data-testid="queued-decorators"], [data-testid="user-message-actions"], [data-screenshot-volatile], time, svg'));
    const parts = [];
    const walker = document.createTreeWalker(step, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      let cur = node.parentElement;
      let ignored = false;
      while (cur && cur !== step) {
        if (skipNodes.has(cur)) {
          ignored = true;
          break;
        }
        cur = cur.parentElement;
      }
      if (ignored) continue;
      const t = (node.nodeValue || '').trim();
      if (t && !/^\d+\s*(?:s|m|h|d)?\s*ago$/i.test(t) && t !== 'You') parts.push(t);
    }
    const text = parts.join(' ').replace(/\s+/g, ' ').trim();
    const hanMatches = text.match(/[\u4e00-\u9fff]/g);
    return hanMatches && hanMatches.length >= 2 ? text : '';
  }

  function trimDirectiveTail(clauses) {
    const tailRe = /^(?:给个?.*例子|举个?例子|附带?例子|简短说明|简明回答|说清.*|两三句话.*|用.*回答|请简述|谢谢|感谢).*$/;
    const filtered = clauses.filter((c, i) => !(i > 0 && i === clauses.length - 1 && tailRe.test(c)));
    return filtered.length > 0 ? filtered : clauses;
  }

  function deriveZhTitleFromPrompt(promptText) {
    const clean = (promptText || '').replace(/\s+/g, ' ').trim();
    const sentences = clean.split(/[。！？!?\n；;]+/).map((s) => s.trim()).filter(Boolean);
    let first = sentences.find((s) => (s.match(/[\u4e00-\u9fff]/g) || []).length >= 2) || '';
    if (!first) return '';

    const prefixRe = /^(?:你好|您好|请问|麻烦(?:你|您)?|请(?:帮我)?|帮我|能不能|可以(?:帮我)?|能否|顺便|我想(?:问一下|知道|了解)?|想问(?:一下)?|用[一二三四五六七八九十两几\d]+个?[句字段话]+(?:来讲|来说|说|说明|解释|概括)?|简短地?|简单地?|通俗地?|详细地?|快速地?)[，,\s]*/;
    const verbRe = /^(?:讲一讲|讲讲|说一说|说说|解释一下|解释下|解释|介绍一下|介绍下|介绍|聊一聊|聊聊|告诉我|回答一下|回答|总结一下|总结|分析一下|分析|给个|写一下|写个)[，,\s]*/;
    for (let i = 0; i < 4; i++) {
      const next = first.replace(prefixRe, '').trim();
      if (next === first) break;
      if ((next.match(/[\u4e00-\u9fff]/g) || []).length >= 2) first = next;
    }
    const afterVerb = first.replace(verbRe, '').trim();
    if ((afterVerb.match(/[\u4e00-\u9fff]/g) || []).length >= 2) first = afterVerb;
    first = first.replace(/[，,：:\s]+$/, '');
    if (first.length <= 18) return first;

    let clauses = first.split(/[，,]+/).map((c) => c.trim()).filter(Boolean);
    clauses = trimDirectiveTail(clauses);
    const joined = clauses.join('，');
    if (joined.length <= 18) return joined;

    const focusRe = /[几多少怎为何哪谁吗]/;
    const focusClause = clauses.find((c, idx) => idx > 0 && focusRe.test(c) && c.length >= 6 && c.length <= 18);
    if (focusClause) return focusClause;
    if (clauses[0] && clauses[0].length >= 6 && clauses[0].length <= 18) return clauses[0];

    let candidate = joined.slice(0, 17).replace(/[，,、\s]+$/, '');
    return candidate ? candidate + '…' : '';
  }

  function findFirstVisibleTextNode(root) {
    if (!root) return null;
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      if (node.parentElement?.closest?.('svg, input, textarea, [data-agy-hans-ui]')) continue;
      if ((node.nodeValue || '').trim()) return node;
    }
    return null;
  }

  function scheduleTitleResync() {
    if (cancelled || lang !== 'zh' || titleResyncTimers.length > 0) return;
    titleResyncTimers.push(setTimeout(() => {
      if (!cancelled && lang === 'zh') syncChineseConversationTitles(true);
    }, 1200));
    titleResyncTimers.push(setTimeout(() => {
      titleResyncTimers = [];
      if (!cancelled && lang === 'zh') syncChineseConversationTitles(true);
    }, 3200));
  }

  function syncChineseConversationTitles(fromTimer = false) {
    if (cancelled || lang !== 'zh' || typeof document === 'undefined') return;
    const titleMap = loadAutoTitleMap();
    let mapChanged = false;

    const convoView = document.querySelector('[data-testid="conversation-view"], [data-testid="side-question-tab-conversation"]');
    const promptText = convoView ? extractFirstChineseUserPrompt(convoView) : '';
    const segments = Array.from(document.querySelectorAll('[data-testid="breadcrumb-segment"]'));

    if (convoView && segments.length > 0) {
      const titleSeg = segments[segments.length - 1];
      if (!titleSeg.querySelector('input, textarea') &&
          (titleSeg.hasAttribute('data-tooltip-id') || segments.length >= 2 || promptText)) {
        const textNode = findFirstVisibleTextNode(titleSeg);
        if (textNode) {
          const tracked = originals.texts.get(textNode);
          const orig = (tracked ? tracked.orig : (textNode.nodeValue || '')).trim();
          if (isAutoEnglishTitle(orig)) {
            let zhTitle = titleMap[orig];
            if (!zhTitle && promptText) {
              zhTitle = deriveZhTitleFromPrompt(promptText);
              if (zhTitle) {
                titleMap[orig] = zhTitle;
                mapChanged = true;
              }
            }
            if (zhTitle) {
              if (textNode.nodeValue !== zhTitle) writeText(textNode, zhTitle);
              textNode.__zh_patched = true;
              if (document.title && document.title.includes(orig)) {
                if (originalDocTitle === null) originalDocTitle = document.title;
                const nextTitle = originalDocTitle.includes(orig)
                  ? originalDocTitle.replace(orig, () => zhTitle)
                  : document.title.replace(orig, () => zhTitle);
                if (document.title !== nextTitle) document.title = nextTitle;
              }
            }
          }
        }
      }
    }

    if (!fromTimer && promptText) {
      const lastSeg = segments[segments.length - 1];
      const curTitleNode = lastSeg ? findFirstVisibleTextNode(lastSeg) : null;
      const curVal = curTitleNode ? (curTitleNode.nodeValue || '').trim() : '';
      if (!curVal || !CJK_CHAR_RE.test(curVal)) scheduleTitleResync();
    }

    const rowNodes = document.querySelectorAll('[data-testid^="conversation-row-"], [data-testid="side-question-row"]');
    for (const row of rowNodes) {
      const walker = document.createTreeWalker(row, NodeFilter.SHOW_TEXT);
      for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        if (node.parentElement?.closest?.('svg, button')) continue;
        const tracked = originals.texts.get(node);
        const raw = tracked ? tracked.orig : (node.nodeValue || '');
        const trimmed = raw.trim();
        const mapped = trimmed ? titleMap[trimmed] : '';
        if (mapped) {
          const nextVal = raw.replace(trimmed, () => mapped);
          if (node.nodeValue !== nextVal) writeText(node, nextVal);
          node.__zh_patched = true;
        }
      }
    }

    if (mapChanged) saveAutoTitleMap(titleMap);
  }

  function applyChinese(resetMarks) {"""

    js = replace_once(js, "  function applyChinese(resetMarks) {", title_module, "title_module")

    apply_anchor = """    translateNode(document);
  }"""
    apply_patched = """    translateNode(document);
    syncChineseConversationTitles();
  }"""
    js = replace_once(js, apply_anchor, apply_patched, "applyChinese_end")

    flush_anchor = """    flushScheduler = createFlushScheduler((batchNodes, batchElements) => {
      if (cancelled || lang !== 'zh') return;
      for (const node of batchNodes) translateNode(node);
      for (const element of batchElements) translateElement(element);
    });"""
    flush_patched = """    flushScheduler = createFlushScheduler((batchNodes, batchElements) => {
      if (cancelled || lang !== 'zh') return;
      for (const node of batchNodes) translateNode(node);
      for (const element of batchElements) translateElement(element);
      syncChineseConversationTitles();
    });"""
    js = replace_once(js, flush_anchor, flush_patched, "flushScheduler")
except AnchorError as exc:
    sys.stderr.write(f"[警告] 增强补丁部分锚点与新版上游词库不匹配 ({exc})，已自动降级为原生词库。\n")
    js = raw_js.replace("\r\n", "\n")

final_content = header_comment + "\n" + js.rstrip() + "\n"
overlay_dir = os.path.dirname(overlay_path)
os.makedirs(overlay_dir, exist_ok=True)
fd, tmp_path = tempfile.mkstemp(prefix=".antigravity-hans-overlay.", suffix=".tmp", dir=overlay_dir)
try:
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        f.write(final_content)
    os.chmod(tmp_path, 0o644)
    os.replace(tmp_path, overlay_path)
except Exception:
    if os.path.exists(tmp_path):
        os.unlink(tmp_path)
    raise
