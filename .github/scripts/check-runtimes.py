"""Check declared runtimes; EOL fails, newer releases and unavailable data warn."""

import argparse
import datetime as dt
import json
from pathlib import Path
import re
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET


def scalar(path, key):
    if not path.exists():
        return []
    return re.findall(
        rf"^\s*{re.escape(key)}:\s*['\"]?([\w.-]+)",
        path.read_text(), re.MULTILINE,
    )


def declarations(root):
    pins = []
    for directory, workflow, key, product in [
        ('java', 'java.yml', 'java-version', 'eclipse-temurin'),
        ('tools/oracle', 'oracle.yml', 'python-version', 'python'),
        ('ipad', 'ipad.yml', 'xcode-version', 'xcode'),
    ]:
        if not (root / directory).exists():
            print(f'SKIP {directory}: not present')
            continue
        values = scalar(root / '.github/workflows' / workflow, key)
        if directory == 'java':
            pom = root / 'java/pom.xml'
            if pom.exists():
                tree = ET.parse(pom)
                for tag in ('maven.compiler.release', 'java.version'):
                    values += [node.text for node in tree.findall(f'.//{{*}}{tag}')]
        if directory == 'ipad':
            project = root / 'ipad/project.yml'
            values += scalar(project, 'xcodeVersion')
            pins += [('ios', value) for value in scalar(project, 'iOS')]
        if not values:
            print(f'::warning::No {product} pin found in {directory}')
        pins += [(product, value) for value in values]
    return sorted(set(pins))


def version(value):
    return tuple(int(part) for part in value.split('.'))


def expired(value, today):
    return value is True or (isinstance(value, str) and value <= today)


def assess(product, pin, releases, today):
    released = [r for r in releases if r['releaseDate'] <= today]
    match = next((r for r in released if
                  version(pin)[:len(version(r['cycle']))] == version(r['cycle'])), None)
    if not match:
        print(f'::warning::{product} {pin}: no lifecycle data for this cycle')
        return False
    if expired(match.get('eol', False), today):
        print(f'::error::{product} {pin}: EOL ({match["eol"]})')
        return True
    print(f'OK {product} {pin}: EOL {match.get("eol", "unknown")}')
    candidates = [r for r in released if not expired(r.get('eol', False), today)]
    if product == 'eclipse-temurin':
        candidates = [r for r in candidates if r.get('lts')]
    if candidates:
        latest = max(candidates, key=lambda r: version(r['cycle']))
        if version(latest['cycle']) > version(match['cycle']):
            kind = 'LTS' if product == 'eclipse-temurin' else 'supported cycle'
            print(f'::warning::{product} {pin}: newer {kind} {latest["cycle"]} available')
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path('.'))
    args = parser.parse_args()
    failed = False
    cache = {}
    for product, pin in declarations(args.root):
        if pin in ('latest', 'latest-stable'):
            print(f'OK {product}: floating selector {pin}')
            continue
        if not re.fullmatch(r'\d+(\.\d+)*', pin):
            print(f'::warning::{product}: unsupported version expression {pin}')
            continue
        if product not in cache:
            try:
                with urllib.request.urlopen(
                    f'https://endoflife.date/api/{product}.json', timeout=20,
                ) as response:
                    cache[product] = json.load(response)
            except (OSError, ValueError) as error:
                print(f'::warning::{product}: lifecycle data unavailable: {error}')
                cache[product] = None
        if cache[product] is not None:
            failed |= assess(product, pin, cache[product], dt.date.today().isoformat())
    return int(failed)


if __name__ == '__main__':
    raise SystemExit(main())
