'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const root = path.resolve(__dirname, '..');
const template = fs.readFileSync(path.join(root, 'lib/overlay.js'), 'utf8');
const index = JSON.parse(fs.readFileSync(path.join(root, 'locales/index.json'), 'utf8'));
class Element {
  constructor(tag = 'div', attributes = {}, parent = null) {
    this.tag = tag; this.attributes = {...attributes}; this.parentElement = parent;
    this.nodeType = 1; this.isConnected = true;
  }
  getAttribute(name) { return this.attributes[name] ?? null; }
  setAttribute(name, value) { this.attributes[name] = value; }
  hasAttribute(name) { return Object.hasOwn(this.attributes, name); }
  closest(selectors) {
    for (let current = this; current; current = current.parentElement) {
      for (let selector of selectors.split(',').map(s => s.trim())) {
        if (selector === current.tag) return current;
        if (selector[0] === '.' && (current.attributes.class || '').split(' ').includes(selector.slice(1))) return current;
        const match = selector.match(/^\[([^=\]^]+)(\^?=)?"?([^\]"]*)"?\]$/);
        if (match) {
          const value = current.getAttribute(match[1]);
          if (value !== null && (!match[2] || (match[2] === '^=' ? value.startsWith(match[3]) : value === match[3]))) return current;
        }
      }
    }
    return null;
  }
}
function text(value, parent = new Element()) {
  return {nodeType: 3, nodeValue: value, parentElement: parent, isConnected: true};
}
function fixture() {
  const label = text('Settings');
  const file = text('Editing foo.js');
  const greeting = text('Hi Alice, what can we get done today?');
  const ago = text('8m ago');
  const tooltip = new Element('button', {'title':'Copy','aria-label':'Copy'});
  const user = text('Settings', new Element('div', {'data-testid':'user-message-bubble'}));
  const code = text('Settings', new Element('code'));
  const input = text('Settings', new Element('div', {'contenteditable':'true'}));
  const title = text('Settings', new Element('div', {'data-testid':'conversation-row-abc'}));
  const response = new Element('div', {'aria-label':'Agent response'});
  const prose = text('Settings', response);
  const button = text('Copy', new Element('button', {}, response));
  const nodes = [label,file,greeting,ago,tooltip,user,code,input,title,response,prose,button];
  const document = {
    readyState: 'complete', documentElement:{lang:'en'},
    createTreeWalker() { let i = 0; return {nextNode: () => nodes[i++] || null}; }
  };
  const callbacks = [];
  const window = {_VSCODE_NLS_MESSAGES:['Settings','unlisted string','{0}']};
  const context = vm.createContext({
    window, document, Intl, Map, Node:{TEXT_NODE:3}, NodeFilter:{SHOW_TEXT:4,SHOW_ELEMENT:1},
    MutationObserver:class { constructor(callback) {this.callback=callback;callbacks.push(callback);} observe() {} disconnect() {} },
    queueMicrotask: callback => callbacks.push(callback)
  });
  window.addEventListener = () => {};
  window.removeEventListener = () => {};
  return {context,window,document,label,file,greeting,ago,tooltip,user,code,input,title,prose,button,callbacks};
}
function inject(f, code) {
  const locale = JSON.parse(fs.readFileSync(path.join(root,'locales',code+'.json'),'utf8'));
  vm.runInContext(template.replace('/*__AGY_LOCALE__*/', JSON.stringify(locale)), f.context);
  return locale;
}
for (const code of Object.keys(index)) {
  const f = fixture(), locale = inject(f, code);
  assert.equal(f.label.nodeValue, locale.phrases.Settings);
  assert.equal(f.file.nodeValue, locale.phrases.Editing+' foo.js');
  assert.equal(f.greeting.nodeValue, locale.greetings[0].replace('{name}','Alice'));
  assert.equal(f.ago.nodeValue, new Intl.RelativeTimeFormat(code,{numeric:'auto'}).format(-8,'minute'));
  assert.equal(f.tooltip.getAttribute('title'),locale.phrases.Copy);
  assert.equal(f.button.nodeValue,locale.phrases.Copy);
  assert.equal(f.window._VSCODE_NLS_MESSAGES[0],locale.phrases.Settings);
  for (const key of ['user','code','input','title','prose']) assert.equal(f[key].nodeValue,'Settings',code+' must preserve '+key);
  assert.equal(f.document.documentElement.lang,code);
  const count=f.callbacks.length;
  inject(f,code);
  assert.equal(f.callbacks.length,count,'identical injection must be a no-op');
  // The application replaces a previously translated label. Preserve its latest source.
  f.label.nodeValue='Open Folder';
  f.callbacks[0]();
  f.callbacks.at(-1)();
  assert.equal(f.label.nodeValue,locale.phrases['Open Folder']);
  f.window.__antigravityZhPatchCleanup();
  assert.equal(f.label.nodeValue,'Open Folder');
  assert.equal(f.file.nodeValue,'Editing foo.js');
  assert.equal(f.tooltip.getAttribute('title'),'Copy');
  assert.equal(f.window._VSCODE_NLS_MESSAGES[0],'Settings');
  assert.equal(f.document.documentElement.lang,'en');
  console.log('PASS overlay translation, content boundaries, NLS, restoration:', code);
}
const f=fixture();
inject(f,'ja');
inject(f,'ko');
const koPhrases = JSON.parse(fs.readFileSync(path.join(root,'locales/ko.json'))).phrases;
assert.equal(f.label.nodeValue,koPhrases.Settings);
f.window.__antigravityZhSetLang('en');
assert.equal(f.label.nodeValue,'Settings');
assert.equal(f.window._VSCODE_NLS_MESSAGES[0],'Settings');
assert.equal(f.window.__antigravityZhPatchInstalled,true);
f.window.__antigravityZhSetLang('ko');
assert.equal(f.label.nodeValue,koPhrases.Settings);
assert.equal(f.window._VSCODE_NLS_MESSAGES[0],koPhrases.Settings);
assert.equal(f.document.documentElement.lang,'ko');
console.log('PASS language switch ja -> ko -> original -> ko');
{
  const early = fixture();
  early.document.readyState = 'loading';
  early.document.documentElement = null;
  let domLoadedHandler = null;
  let domLoadedOnce = false;
  early.window.addEventListener = (event, handler, opts) => {
    if (event === 'DOMContentLoaded') {
      domLoadedHandler = handler;
      domLoadedOnce = Boolean(opts && opts.once);
    }
  };
  let removedHandler = null;
  early.window.removeEventListener = (event, handler) => {
    if (event === 'DOMContentLoaded') removedHandler = handler;
  };
  const zhLocale = inject(early, 'zh-CN');
  assert.equal(typeof domLoadedHandler, 'function');
  assert.equal(domLoadedOnce, true);
  assert.equal(early.label.nodeValue, 'Settings');
  early.document.readyState = 'interactive';
  early.document.documentElement = {lang: 'en'};
  domLoadedHandler();
  assert.equal(early.document.documentElement.lang, 'zh-CN');
  assert.equal(early.label.nodeValue, zhLocale.phrases.Settings);
  early.window.__antigravityZhPatchCleanup();
  assert.equal(removedHandler, domLoadedHandler);
  assert.equal(early.document.documentElement.lang, 'en');
  assert.equal(early.label.nodeValue, 'Settings');
  console.log('PASS early-document null documentElement guard: zh-CN');
}
{
  // 上游 Antigravity-Hans 词库已声明在当前文档生效时，zh-CN 内置词库不得 cleanup 掉它，
  // 否则只存在于上游词库的文案（Turbo、This Computer 等）会漏翻。
  // 冷启动时 document 仍处于 loading，上游主体会推迟到 DOMContentLoaded 才执行，
  // 因此 __antigravityZhSetLang 往往还没挂载；守卫只能依赖同步置位的 installed 标记。
  const f = fixture();
  let cleaned = false;
  f.window.__antigravityZhPatchInstalled = true;
  f.window.__observedDocument = f.document;
  f.window.__antigravityZhPatchRequestedFingerprint = 'fp-fallback';
  f.window.__antigravityZhPatchCleanup = () => { cleaned = true; };
  inject(f, 'zh-CN');
  assert.equal(cleaned, false, 'zh-CN must not tear down the upstream overlay');
  assert.equal(f.window.__antigravityZhPatchFingerprint, 'fp-fallback');
  assert.equal(f.label.nodeValue, 'Settings');
  assert.equal(f.tooltip.getAttribute('title'), 'Copy');
  assert.equal(f.document.documentElement.lang, 'en');
  assert.equal(f.window.__antigravityI18nInstalled, undefined);
  console.log('PASS zh-CN defers to upstream Antigravity-Hans overlay before DOMContentLoaded');

  // __observedDocument 不是当前 document（残留状态）时，zh-CN 不得跳过安装。
  const stale = fixture();
  let staleCleaned = false;
  stale.window.__antigravityZhPatchInstalled = true;
  stale.window.__observedDocument = {};
  stale.window.__antigravityZhPatchCleanup = () => { staleCleaned = true; };
  const zhLocale = inject(stale, 'zh-CN');
  assert.equal(staleCleaned, true, 'zh-CN must reinstall when __observedDocument does not match current document');
  assert.equal(stale.label.nodeValue, zhLocale.phrases.Settings);
  assert.equal(stale.window.__antigravityI18nInstalled, true);
  console.log('PASS zh-CN does not defer when __observedDocument is stale');

  // 内置 overlay 已经接管时仍应重新安装，避免本地切换语言后再也装不回来。
  const g = fixture();
  let reclaimed = false;
  g.window.__antigravityZhPatchInstalled = true;
  g.window.__observedDocument = g.document;
  g.window.__antigravityI18nInstalled = true;
  g.window.__antigravityZhPatchCleanup = () => { reclaimed = true; };
  inject(g, 'zh-CN');
  assert.equal(reclaimed, true, 'zh-CN must reclaim when the built-in overlay is already installed');
  console.log('PASS zh-CN reclaims when the built-in overlay is already installed');
}
{
  // 2.36 词条、防误译保护与 patchNls 单次执行验证。
  const turbo = text('Turbo');
  const scope = text('This Computer');
  const sideFollowup = text('Settings', new Element('div', {'data-testid':'side-question-followup-user'}));
  const fileTitle = text('Settings', new Element('span', {'data-testid':'file-title-name'}));
  const branchPill = text('Settings', new Element('span', {'data-testid':'branch-pill-label'}));
  const mdRoot = new Element('div', {'data-markdown-root':''});
  const markdownProse = text('Settings', mdRoot);
  const markdownCtrl = text('Copy', new Element('button', {'data-testid':'code-block-preview-toggle'}, mdRoot));
  const coordStrong = text('Settings', new Element('strong', {}, new Element('div', {'data-testid':'coordinator-welcome'})));
  const projectHdr = new Element('div', {'data-testid':'project-header', 'data-project-label':'Auto'});
  const projectName = text('Auto', new Element('span', {}, projectHdr));
  const projectAction = text('Settings', new Element('span', {}, projectHdr));
  const nodes = [turbo, scope, sideFollowup, fileTitle, branchPill, mdRoot, markdownProse, markdownCtrl, coordStrong, projectHdr, projectName, projectAction];
  const document = {
    readyState: 'complete', documentElement:{lang:'en'},
    createTreeWalker() { let i = 0; return {nextNode: () => nodes[i++] || null}; }
  };
  const callbacks = [];
  const window = {_VSCODE_NLS_MESSAGES:['Settings','unlisted string','{0}'], addEventListener(){}, removeEventListener(){}};
  const context = vm.createContext({
    window, document, Intl, Map, Node:{TEXT_NODE:3}, NodeFilter:{SHOW_TEXT:4,SHOW_ELEMENT:1},
    MutationObserver:class { constructor(callback) {this.callback=callback;callbacks.push(callback);} observe() {} disconnect() {} },
    queueMicrotask: callback => callbacks.push(callback)
  });
  const jaLocale = inject({context}, 'ja');
  assert.equal(turbo.nodeValue, jaLocale.phrases.Turbo);
  assert.equal(scope.nodeValue, jaLocale.phrases['This Computer']);
  assert.equal(sideFollowup.nodeValue, 'Settings');
  assert.equal(fileTitle.nodeValue, 'Settings');
  assert.equal(branchPill.nodeValue, 'Settings');
  assert.equal(markdownProse.nodeValue, 'Settings');
  assert.equal(markdownCtrl.nodeValue, jaLocale.phrases.Copy);
  assert.equal(coordStrong.nodeValue, 'Settings');
  assert.equal(projectName.nodeValue, 'Auto');
  assert.equal(projectAction.nodeValue, jaLocale.phrases.Settings);
  assert.equal(window._VSCODE_NLS_MESSAGES[0], jaLocale.phrases.Settings);
  // 后续 MutationObserver sweep 不应再重复执行 patchNls。
  window._VSCODE_NLS_MESSAGES[1] = 'Copy';
  callbacks[0]();
  callbacks.at(-1)();
  assert.equal(window._VSCODE_NLS_MESSAGES[1], 'Copy');
  console.log('PASS 2.36 keys, protected selectors, and single-run patchNls');
}
