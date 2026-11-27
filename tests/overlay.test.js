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
assert.equal(f.label.nodeValue,JSON.parse(fs.readFileSync(path.join(root,'locales/ko.json'))).phrases.Settings);
f.window.__antigravityZhSetLang('en');
assert.equal(f.label.nodeValue,'Settings');
console.log('PASS language switch ja -> ko -> original');
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
  // 上游 Antigravity-Hans 词库已生效时，zh-CN 内置词库不得 cleanup 掉它，
  // 否则只存在于上游词库的文案（Turbo、This Computer 等）会漏翻。
  const f = fixture();
  let cleaned = false;
  f.window.__antigravityZhPatchInstalled = true;
  f.window.__antigravityZhSetLang = () => {};
  f.window.__antigravityZhPatchCleanup = () => { cleaned = true; };
  inject(f, 'zh-CN');
  assert.equal(cleaned, false, 'zh-CN must not tear down the upstream overlay');
  assert.equal(f.label.nodeValue, 'Settings');
  assert.equal(f.tooltip.getAttribute('title'), 'Copy');
  assert.equal(f.document.documentElement.lang, 'en');
  assert.equal(f.window.__antigravityI18nInstalled, undefined);
  console.log('PASS zh-CN defers to upstream Antigravity-Hans overlay');
}
