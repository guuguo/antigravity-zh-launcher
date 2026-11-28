#!/usr/bin/env python3
"""Offline regression tests. All writable paths and app bundles live in a temp HOME."""
import ast
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
INDEX = json.loads((ROOT / 'locales/index.json').read_text())

class LauncherTests(unittest.TestCase):
    def run_command(self, *args, env=None, ok=True):
        result = subprocess.run(args, cwd=ROOT, env=env, text=True, capture_output=True)
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout)
        return result

    def test_dictionaries_and_plugins(self):
        self.assertEqual(set(INDEX), {'zh-CN','zh-TW','ja','ko','es','fr','de','ru','pt-BR'})
        keys = None
        for code, meta in INDEX.items():
            data = json.loads((ROOT / 'locales' / (code + '.json')).read_text())
            self.assertEqual(data['code'], code)
            self.assertTrue(all(isinstance(v, str) and v.strip() for v in data['phrases'].values()))
            self.assertGreater(len(data['phrases']), 250)
            self.assertEqual(len({key.lower() for key in data['phrases']}), len(data['phrases']))
            if keys is None:
                keys = set(data['phrases'])
            self.assertEqual(set(data['phrases']), keys)
            self.assertEqual(len(data['greetings']), 7)
            self.assertTrue(all(data['greetings']))
            plugin = ROOT / 'plugins' / meta['pluginName']
            manifest = json.loads((plugin / 'plugin.json').read_text())
            self.assertEqual(manifest['name'], meta['pluginName'])
            self.assertIs(manifest['disabled'], True)
            self.assertTrue((plugin / 'rules/AGENTS.md').read_text().strip())
        self.assertEqual(INDEX['zh-CN']['command'], 'agy-zh')
        self.assertEqual(INDEX['zh-CN']['appName'], 'Antigravity 中文')
        self.assertEqual(len({m['bundleId'] for m in INDEX.values()}), 9)

    def test_syntax(self):
        for file in ['install.sh','uninstall.sh','bin/agy-zh']:
            self.run_command('bash', '-n', str(ROOT / file))
            # Bash's parser does not validate Python heredocs.
            source = (ROOT / file).read_text()
            for body in re.findall(r"<<'PY'\n(.*?)\nPY", source, re.S):
                ast.parse(body, filename=file)
        for file in (ROOT / 'lib').glob('*.py'):
            ast.parse(file.read_text(), filename=str(file))
        self.run_command('node', '--check', str(ROOT / 'lib/overlay.js'))
        ps1_bytes = (ROOT / 'bin/agy-zh.ps1').read_bytes()
        self.assertTrue(ps1_bytes.startswith(b'\xef\xbb\xbf'))
        ps1 = (ROOT / 'bin/agy-zh.ps1').read_text()
        self.assertNotIn('return ,$pids', ps1)
        self.assertNotIn('/IM Antigravity.exe', ps1)
        self.assertNotIn('wscript.exe', ps1)
        self.assertNotIn('//B', ps1)
        self.assertNotIn('?.', ps1)
        self.assertNotRegex(ps1, r'\.ArgumentList\b')
        self.assertNotIn('.Split(@(', ps1)
        self.assertNotRegex(ps1, r'&\s+\$drainState\b')
        self.assertRegex(ps1, r'\.\s+\$drainState\b')
        self.assertIn('DnsSafeHost', ps1)
        self.assertIn('CreateNoWindow', ps1)
        self.assertIn('Write-AgyLog', ps1)
        self.assertIn('Focus-VisibleWindowForPids', ps1)
        self.assertIn('falling back to in-process watcher', ps1)
        self.assertIn('Start-CdpWatchLoop -GuiMode $true -FixedPort $targetPort -LaunchApp $needLaunch -QuietConsole $false', ps1)
        self.assertIn('Start-AntigravityProcess', ps1)
        self.assertIn('Re-injected target after reload', ps1)
        self.assertIn("return 'already'", ps1)
        self.assertIn("return 'injected'", ps1)
        self.assertNotIn('if ($injectedUrls.ContainsKey($tid) -and $injectedUrls[$tid] -eq $tUrl) { continue }', ps1)
        self.assertNotRegex(ps1, r'&\s+\$sweepTargets\b')
        self.assertRegex(ps1, r'\.\s+\$sweepTargets\b')
        self.assertIn(
            'https://raw.githubusercontent.com/yuexps/Antigravity-Hans/main/resources/antigravity-hans-overlay.js',
            ps1,
        )
        self.assertNotIn('/Antigravity-Hans/main/antigravity-hans-overlay.js', ps1)
        agy_zh = (ROOT / 'bin/agy-zh').read_text()
        self.assertNotIn('if t["id"] not in injected_ids:', agy_zh)
        self.assertIn('return "already"', agy_zh)
        self.assertIn('return "injected"', agy_zh)
        self.assertIn(
            'https://raw.githubusercontent.com/yuexps/Antigravity-Hans/main/resources/antigravity-hans-overlay.js',
            agy_zh,
        )
        self.assertNotIn('/Antigravity-Hans/main/antigravity-hans-overlay.js', agy_zh)
        self.assertNotIn('?.', (ROOT / 'lib/locale.ps1').read_text())
        self.assertNotRegex((ROOT / 'lib/zh-overlay.ps1').read_text(), r'\$[A-Za-z0-9_:]+\?\.')
        self.assertIn('Write-Warning', (ROOT / 'lib/zh-overlay.ps1').read_text())
        self.assertIn('side-question-followup-user', (ROOT / 'lib/zh-overlay.ps1').read_text())
        self.assertIn('agy-zh-v8', ps1)
        shortcut_fn = re.search(r'function New-ZhShortcut\s*\{(.*?)\n\}', ps1, re.S)
        self.assertIsNotNone(shortcut_fn)
        self.assertIn('powershell.exe', shortcut_fn.group(1))
        self.assertIn('--gui', shortcut_fn.group(1))
        for line in ps1.splitlines():
            if 'taskkill.exe' in line:
                self.assertIn('try {', line)
            if '.GetAwaiter().GetResult()' in line:
                self.assertRegex(line.strip(), r'^\$[A-Za-z0-9_:]+\s*=')
        with tempfile.TemporaryDirectory(prefix='agy-build-') as tmp:
            base = Path(tmp, 'base.js')
            # Test the existing anchor-mismatch fallback without using the network.
            base.write_text('window.__antigravityZhPatchInstalled = true;\n')
            for code in INDEX:
                dest = Path(tmp, code + '.js')
                self.run_command('python3', str(ROOT / 'lib/locale.py'), 'build', code, str(dest), str(base), 'false')
                self.run_command('node', '--check', str(dest))

    def test_argument_errors_and_dry_runs(self):
        for file in ['install.sh','uninstall.sh','bin/agy-zh']:
            for args in [('--lang',), ('--lang','en'), ('--lang=../../bad',), ('--unknown',)]:
                self.run_command('bash', str(ROOT / file), *args, ok=False)
            self.run_command('bash', str(ROOT / file), '--help')
        for file in ['install.sh','uninstall.sh']:
            for code in INDEX:
                self.assertIn('dry-run', self.run_command('bash', str(ROOT/file), '--lang', code, '--dry-run').stdout)

    def test_install_coexistence_and_uninstall(self):
        with tempfile.TemporaryDirectory(prefix="agy regression ' space ") as tmp:
            home = Path(tmp)
            apps = home / 'Applications'
            icon = apps / 'Antigravity.app/Contents/Resources/icon.icns'
            icon.parent.mkdir(parents=True)
            icon.write_bytes(b'original icon sentinel')
            base = home / 'base.js'
            base.write_text('window.__antigravityZhPatchInstalled = true;\n')
            env = dict(os.environ, HOME=tmp, AGY_ZH_APPS_DIR=str(apps),
                       GEMINI_CONFIG_DIR=str(home/'config'), AGY_ZH_DATA_DIR=str(home/'.local/bin'),
                       AGY_ZH_OVERLAY_URL=base.as_uri())
            config = home/'config/config.json'
            config.parent.mkdir()
            config.write_text(json.dumps({'sentinel':42,'plugins':{'unrelated':{'enabled':True}}}))
            for code, meta in INDEX.items():
                args = [] if code == 'zh-CN' else ['--lang', code]
                self.run_command('bash', str(ROOT/'install.sh'), *args, env=env)
                local_bin = home / '.local/bin'
                self.assertTrue((local_bin / meta['command']).is_file())
                self.assertTrue((local_bin/'agy-i18n/installed'/code).is_file())
                info = apps / (meta['appName']+'.app') / 'Contents/Info.plist'
                with info.open('rb') as f:
                    plist = plistlib.load(f)
                self.assertEqual(plist['CFBundleName'], meta['appName'])
                self.assertEqual(plist['CFBundleIdentifier'], meta['bundleId'])
                launcher = info.parent/'MacOS/launcher'
                self.run_command('bash','-n',str(launcher))
                self.assertIn("--lang '"+code+"'",launcher.read_text())
                # Language aliases also resolve paths containing spaces and apostrophes.
                self.run_command(str(local_bin/meta['command']), 'status', env=env)
                self.assertFalse(json.loads(config.read_text())['plugins'][meta['pluginName']]['enabled'])
            cli = home/'.local/bin/agy-zh'
            self.run_command(str(cli),'--lang','ja','prompt','on',env=env)
            self.run_command(str(cli),'prompt','on','--lang','ko',env=env)
            data=json.loads(config.read_text())
            self.assertFalse(data['plugins'][INDEX['ja']['pluginName']]['enabled'])
            self.assertTrue(data['plugins'][INDEX['ko']['pluginName']]['enabled'])
            self.assertTrue(data['plugins']['unrelated']['enabled'])
            # Default uninstall keeps the shared CLI while other language entries exist.
            self.run_command('bash',str(ROOT/'uninstall.sh'),env=env)
            self.assertFalse((apps/'Antigravity 中文.app').exists())
            self.assertTrue(cli.exists())
            self.run_command(str(home/'.local/bin/agy-ja'),'status',env=env)
            for code,meta in list(INDEX.items())[1:]:
                self.run_command('bash',str(ROOT/'uninstall.sh'),'--lang',code,'--purge',env=env)
                self.assertFalse((apps/(meta['appName']+'.app')).exists())
                self.assertFalse((home/'config/plugins'/meta['pluginName']).exists())
            self.assertFalse(cli.exists())
            self.assertFalse((home/'.local/bin/agy-i18n').exists())
            self.assertEqual(icon.read_bytes(), b'original icon sentinel')
            self.assertEqual(json.loads(config.read_text()), {'sentinel':42,'plugins':{'unrelated':{'enabled':True}}})
            # Repeat uninstall and legacy cache purge are harmless.
            self.run_command('bash',str(ROOT/'uninstall.sh'),'--purge',env=env)
            self.assertFalse((home/'.local/bin/antigravity-hans-overlay.base.js').exists())

    def test_remote_pipe_install(self):
        # Exercise the public curl | bash path using file:// sources, offline.
        # Downloaded launcher files have mode 0644 until installed.
        for code in ['zh-CN', 'ja']:
            with tempfile.TemporaryDirectory(prefix='agy-pipe-') as tmp:
                home = Path(tmp)
                base = home / 'base.js'
                base.write_text('window.__antigravityZhPatchInstalled = true;\n')
                env = dict(os.environ, HOME=tmp, AGY_ZH_REPO_RAW=ROOT.as_uri(),
                           AGY_ZH_APPS_DIR=str(home/'apps'), GEMINI_CONFIG_DIR=str(home/'config'),
                           AGY_ZH_DATA_DIR=str(home/'.local/bin'), AGY_ZH_OVERLAY_URL=base.as_uri())
                args = ['bash','-s','--','--no-shortcut']
                if code != 'zh-CN': args += ['--lang',code]
                result = subprocess.run(args, input=(ROOT/'install.sh').read_text(),
                                        cwd=ROOT,env=env,text=True,capture_output=True)
                self.assertEqual(result.returncode,0,result.stdout+result.stderr)
                self.assertTrue((home/'.local/bin/agy-i18n/installed'/code).is_file())
                self.run_command('bash',str(ROOT/'uninstall.sh'),'--lang',code,'--purge',env=env)

    def test_zh_overlay_supports_both_old_and_new_upstream_layouts(self):
        legacy_base = """window.__antigravityZhPatchInstalled = true;
(() => {
  const phrases = new Map([
    ["Settings", "设置"],
  ]);
  const dynamicPatterns = [
    [/(\\d+)\\s*minutes?\\s*ago\\b/gi, '$1 分钟前'],
    [/(\\d+)\\s*hours?\\s*ago\\b/gi, '$1 小时前'],
    [/(\\d+)\\s*days?\\s*ago\\b/gi, '$1 天前'],
    [/(\\d+)\\s*weeks?\\s*ago\\b/gi, '$1 周前'],
    [/(\\d+)\\s*months?\\s*ago\\b/gi, '$1 个月前'],
    [/(\\d+)\\s*years?\\s*ago\\b/gi, '$1 年前'],
  ];
  function translate(value) {
    const trimmed = value.trim();
    const greeting = trimmed.match(/^Hi ([\\s\\S]+?), what can we get done today\\?$/);
    if (greeting) return value.replace(trimmed, () => `你好，${greeting[1]}，今天想完成什么？`);
    if (/^你好，[\\s\\S]+，今天想完成什么？$/.test(trimmed)) return value;
    return value;
  }
  function shouldSkip(node, element) {
    // 跳过用户输入
    if (element.closest('[data-testid="user-input-step"], [aria-label="User message"], [aria-label="用户消息"]')) {
      return true;
    }
    const historyItem = element.closest('[data-testid="conversation-row-sidebar"], [data-cascade-id], .past-conversations');
    // 跳过回复正文（保留控件、折叠步骤栏、变更概览与系统提示卡片）
    const agentResponse = element.closest('[aria-label="Agent response"], [aria-label="智能体回复"]');
    if (agentResponse) {
      if (node.nodeType === Node.ELEMENT_NODE && element === agentResponse) return false;
      const isInteractive = element.closest('button, [role="button"], [class*="action"], [class*="button-container"], [data-testid="cleared-step-notice"], .files-changed-header');
    }
  }
  const sel = [
    '.antigravity-welcome-container',
  ];
  function restoreOriginals() {
    const walker = document.createTreeWalker(document, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      restoreTrackedNode(node);
    }
  }
  window.__antigravityZhPatchCleanup = () => {
    flushScheduler?.cancel();
    restoreIdeNlsMessages();
    removePreferenceSync?.();
  };
  function applyChinese(resetMarks) {
    translateNode(document);
  }
  function run() {
    flushScheduler = createFlushScheduler((batchNodes, batchElements) => {
      if (cancelled || lang !== 'zh') return;
      for (const node of batchNodes) translateNode(node);
      for (const element of batchElements) translateElement(element);
    });
  }
})();
"""
        modular_base = """window.__antigravityZhPatchInstalled = true;
(() => {
  const phrases = new Map([
    ["Settings", "设置"],
  ]);
const dynamicPatterns = [
  [/(\\d+)\\s*minutes?\\s*ago\\b/gi, '$1 分钟前'],
  [/(\\d+)\\s*hours?\\s*ago\\b/gi, '$1 小时前'],
  [/(\\d+)\\s*days?\\s*ago\\b/gi, '$1 天前'],
  [/(\\d+)\\s*weeks?\\s*ago\\b/gi, '$1 周前'],
  [/(\\d+)\\s*months?\\s*ago\\b/gi, '$1 个月前'],
  [/(\\d+)\\s*years?\\s*ago\\b/gi, '$1 年前'],
];
function translate(value) {
  const trimmed = value.trim();
  const greeting = trimmed.match(/^Hi ([\\s\\S]+?), what can we get done today\\?$/);
  if (greeting) return value.replace(trimmed, () => `你好，${greeting[1]}，今天想完成什么？`);
  const greetingBuild = trimmed.match(/^Hey ([\\s\\S]+?), what should we build today\\?$/);
  if (greetingBuild) return value.replace(trimmed, () => `嗨，${greetingBuild[1]}，今天想构建什么？`);
  const greetingNext = trimmed.match(/^Good to see you, ([\\s\\S]+?)\\. What's next\\?$/);
  if (greetingNext) return value.replace(trimmed, () => `很高兴见到你，${greetingNext[1]}。接下来做什么？`);
  const greetingBack = trimmed.match(/^Welcome back, ([\\s\\S]+?)\\. Where should we pick up\\?$/);
  if (greetingBack) return value.replace(trimmed, () => `欢迎回来，${greetingBack[1]}。我们从哪里继续？`);
  if (/^(?:你好，[\\s\\S]+，今天想完成什么？|嗨，[\\s\\S]+，今天想构建什么？|很高兴见到你，[\\s\\S]+。接下来做什么？|欢迎回来，[\\s\\S]+。我们从哪里继续？)$/.test(trimmed)) return value;
  return value;
}
function shouldSkipSubtree(node, element) {
  // 跳过用户输入
  if (element.closest('[data-testid="user-input-step"], [aria-label="User message"], [aria-label="用户消息"]')) {
    return true;
  }
  return false;
}
function shouldSkip(node, element) {
  const historyItem = element.closest('[data-testid="conversation-row-sidebar"], [data-cascade-id]:not([data-testid="conversation-view"]), .past-conversations');
  // 跳过回复正文（保留控件、折叠步骤栏、变更概览与系统提示卡片）
  const agentResponse = element.closest('[aria-label="Agent response"], [aria-label="智能体回复"]');
  if (agentResponse) {
    if (node.nodeType === Node.ELEMENT_NODE && element === agentResponse) return false;
    const isInteractive = element.closest('button, [role="button"], [class*="action"], [class*="button-container"], [data-testid="cleared-step-notice"], .files-changed-header');
  }
}
const antigravityContainerSelector = [
  '.antigravity-welcome-container',
];
  function restoreOriginals() {
    const walker = document.createTreeWalker(document, NodeFilter.SHOW_TEXT | NodeFilter.SHOW_ELEMENT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      restoreTrackedNode(node);
    }
  }
  window.__antigravityZhPatchCleanup = () => {
    flushScheduler?.cancel();
    restoreIdeNlsMessages();
    removePreferenceSync?.();
  };
  function applyChinese(resetMarks) {
    translateNode(document);
  }
  function run() {
    flushScheduler = createFlushScheduler((batchNodes, batchElements) => {
      if (cancelled || lang !== 'zh') return;
      for (const node of batchNodes) translateNode(node);
      for (const element of batchElements) translateElement(element);
    });
  }
})();
"""
        modular_236_base = modular_base.replace(
            '[data-testid="user-input-step"], [aria-label="User message"], [aria-label="用户消息"]',
            '[data-testid="user-input-step"], [data-testid="side-question-followup-user"], [aria-label="User message"], [aria-label="用户消息"]',
        )
        with tempfile.TemporaryDirectory(prefix='agy-layouts-') as tmp:
            for name, content in [('legacy', legacy_base), ('modular', modular_base), ('modular_236', modular_236_base)]:
                base = Path(tmp, f'{name}-base.js')
                out = Path(tmp, f'{name}-out.js')
                base.write_text(content, encoding='utf-8')
                res = self.run_command('python3', str(ROOT / 'lib/zh-overlay.py'), str(base), str(out), 'agy-zh-v8', 'true')
                self.assertNotIn('[警告]', res.stderr)
                built = out.read_text(encoding='utf-8')
                self.assertIn('syncChineseConversationTitles', built)
                self.assertIn('[data-testid="home-greeting"]', built)
                if name == 'modular_236':
                    self.assertIn('[data-testid="side-question-followup-user"]', built)
                self.run_command('node', '--check', str(out))
                full = Path(tmp, f'{name}-full.js')
                self.run_command('python3', str(ROOT / 'lib/locale.py'), 'build', 'zh-CN', str(full), str(base), 'true')
                self.run_command('node', '--check', str(full))

    def test_zh_cn_fallback_without_upstream_overlay(self):
        with tempfile.TemporaryDirectory(prefix='agy-fallback-') as tmp:
            home = Path(tmp)
            missing_url = (home / 'does-not-exist.js').as_uri()
            data_dir = home / '.local/bin'
            env = dict(
                os.environ,
                HOME=tmp,
                AGY_ZH_APPS_DIR=str(home / 'Applications'),
                GEMINI_CONFIG_DIR=str(home / 'config'),
                AGY_ZH_DATA_DIR=str(data_dir),
                AGY_ZH_OVERLAY_URL=missing_url,
            )
            res = self.run_command('bash', str(ROOT / 'install.sh'), '--no-shortcut', env=env)
            self.assertIn('[警告]', res.stderr)
            overlay = data_dir / 'antigravity-hans-overlay.js'
            self.assertTrue(overlay.is_file())
            self.assertIn('__antigravityZhPatchInstalled', overlay.read_text(encoding='utf-8'))
            self.run_command('node', '--check', str(overlay))

            res2 = self.run_command(str(data_dir / 'agy-zh'), 'build-overlay', '--force', env=env)
            self.assertIn('[警告]', res2.stderr)
            self.run_command('node', '--check', str(overlay))

    def test_zh_cn_reuses_cached_base_when_force_refresh_fails(self):
        with tempfile.TemporaryDirectory(prefix='agy-cache-') as tmp:
            home = Path(tmp)
            data_dir = home / '.local/bin'
            data_dir.mkdir(parents=True)
            base = data_dir / 'antigravity-hans-overlay.base.js'
            cached_text = 'window.__antigravityZhPatchInstalled = true;\n// cached-sentinel\n'
            base.write_text(cached_text, encoding='utf-8')
            env = dict(
                os.environ,
                HOME=tmp,
                GEMINI_CONFIG_DIR=str(home / 'config'),
                AGY_ZH_DATA_DIR=str(data_dir),
                AGY_ZH_OVERLAY_URL=(home / 'missing.js').as_uri(),
            )
            res = self.run_command('bash', str(ROOT / 'bin/agy-zh'), 'build-overlay', '--force', env=env)
            self.assertIn('继续使用本地缓存词库', res.stderr)
            self.assertEqual(base.read_text(encoding='utf-8'), cached_text)
            overlay = data_dir / 'antigravity-hans-overlay.js'
            overlay_text = overlay.read_text(encoding='utf-8')
            self.assertIn('agy-zh-v8', overlay_text)
            self.assertIn('// cached-sentinel', overlay_text)
            self.run_command('node', '--check', str(overlay))

if __name__ == '__main__':
    unittest.main(verbosity=2)
