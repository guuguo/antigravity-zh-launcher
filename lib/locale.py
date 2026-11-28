#!/usr/bin/env python3
"""Shared metadata and overlay builder for macOS (stdlib only)."""
import json
import pathlib
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent.parent
index = json.loads((root / 'locales/index.json').read_text(encoding='utf-8'))

def main():
    action, code = sys.argv[1:3]
    if code not in index:
        raise ValueError('不支持的语言 / Unsupported language: ' + code + '; ' + ', '.join(index))
    meta = index[code]
    if action == 'metadata':
        print('\t'.join([meta['appName'], meta['command'], meta['pluginName'], meta['bundleId']]))
    elif action == 'build':
        output = pathlib.Path(sys.argv[3])
        locale = json.loads((root / 'locales' / (code + '.json')).read_text(encoding='utf-8'))
        overlay_tpl = (root / 'lib/overlay.js').read_text(encoding='utf-8')
        i18n_layer = overlay_tpl.replace('/*__AGY_LOCALE__*/', json.dumps(locale, ensure_ascii=True))
        base_path = pathlib.Path(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[4] else None
        force_flag = sys.argv[5] if len(sys.argv) > 5 else 'false'
        if code == 'zh-CN' and base_path is not None and base_path.is_file() and base_path.stat().st_size > 0:
            # Retain the original Chinese enhancement behavior and layer expanded zh-CN dictionary/rules.
            subprocess.run([sys.executable, str(root / 'lib/zh-overlay.py'), str(base_path),
                            str(output), 'agy-zh-v8', force_flag], check=True)
            base_script = output.read_text(encoding='utf-8')
            marker = '/*__AGY_ZH_I18N_LAYER__*/'
            if marker in base_script:
                base_script = base_script.split(marker, 1)[0]
            script = base_script.rstrip() + '\n' + marker + '\n' + i18n_layer
        else:
            script = i18n_layer
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(script, encoding='utf-8')
    else:
        raise ValueError('Unknown action: ' + action)

if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        sys.exit('[错误] ' + str(exc))
