"""Export the running Onsen Atlas public pages for Firebase static preview."""

import argparse
import json
import re
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from urllib.parse import parse_qs, urlencode, urlsplit, urlunsplit
from urllib.request import HTTPRedirectHandler, ProxyHandler, build_opener

from lxml import etree, html


LOCALES = ('ko', 'ja', 'en', 'zh-Hans')
NOTICE = {
    'ko': '공개 승인 자료로 만든 미리보기입니다.',
    'ja': '公開審査済みのデータを使ったプレビューです。',
    'en': 'Preview of the approved public catalogue.',
    'zh-Hans': '此预览使用已批准公开的资料。',
}
STATIC_CSS = re.compile(r'/_next/static/css/[a-z0-9._/-]+\.css')
SLUG = re.compile(r'[a-z0-9]+(?:-[a-z0-9]+)*')


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        return None


def read_public(origin, path):
    opener = build_opener(ProxyHandler({}), NoRedirect())
    with opener.open(origin + path, timeout=15) as response:
        data = response.read(4 * 1024 * 1024 + 1)
    if len(data) > 4 * 1024 * 1024:
        raise ValueError(f'Public preview response too large: {path}')
    return data


def preview_html(data, locale, css):
    document = html.document_fromstring(data.decode('utf-8'))
    if len(document.xpath('//main[@id="main"]')) != 1:
        raise ValueError('Source page did not render the public layout')
    if document.xpath('//*[@role="alert"]'):
        raise ValueError('Source page rendered an error')
    for element in document.xpath('//script|//iframe|//object|//embed|//template|//base|//next-route-announcer'):
        element.drop_tree()
    for element in document.xpath('//*[contains(concat(" ",normalize-space(@class)," ")," filter-box ")]'):
        element.drop_tree()
    for element in document.xpath('//button'):
        element.drop_tree()
    for element in document.xpath('//link'):
        href = element.get('href', '')
        if element.get('rel') == 'stylesheet' and STATIC_CSS.fullmatch(href) and '..' not in href:
            css.add(href)
        else:
            element.drop_tree()
    for element in document.iter():
        if not isinstance(element.tag, str):
            continue
        for attr in tuple(element.attrib):
            if attr.lower().startswith('on') or attr.lower() == 'srcdoc':
                del element.attrib[attr]
        for attr in ('href', 'src', 'action'):
            url = element.get(attr)
            if not url:
                continue
            parts = urlsplit(url)
            if parts.scheme and (parts.scheme != 'https' or parts.username or parts.password):
                del element.attrib[attr]
            elif not parts.scheme and parts.netloc:
                del element.attrib[attr]
            elif not parts.scheme and parts.path.endswith('/onsen/coverage') and parse_qs(parts.query).get('kind') == ['area']:
                element.set(attr, parts.path + '/areas')
            elif not parts.scheme and parts.path.startswith('/') and parts.query:
                element.set(attr, urlunsplit(('', '', parts.path, '', parts.fragment)))
    for link in document.xpath('//a[@href]'):
        if link.get('href', '').startswith('https://'):
            link.set('rel', 'noopener noreferrer')
    label = etree.Element('p', attrib={'class': 'container', 'role': 'note'})
    label.text = NOTICE[locale]
    document.xpath('//main[@id="main"]')[0].insert(0, label)
    return html.tostring(document, encoding='utf-8', method='html', doctype='<!doctype html>')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--origin', default='http://127.0.0.1:55449')
    args = parser.parse_args()
    origin = args.origin.rstrip('/')
    parsed = urlsplit(origin)
    if (parsed.scheme != 'http' or parsed.hostname not in {'127.0.0.1', '::1', 'localhost'}
            or parsed.path or parsed.username or parsed.query or parsed.fragment):
        parser.error('--origin must be the existing loopback site origin')
    root = Path(__file__).resolve().parent.parent
    output = root / '.firebase-preview'
    if output.exists():
        parser.error('Move the previous .firebase-preview directory before creating a new snapshot')
    query = {'scope': 'nationwide', 'limit': 50}
    release = None
    entries = {}
    for kind in ('facility', 'area'):
        page = json.loads(read_public(origin, '/api/v1/onsen-entries?' + urlencode(dict(query, locale='ko', kind=kind))))
        if page['nextCursor'] or not page['releaseId'] or (release and release != page['releaseId']):
            raise ValueError('Snapshot needs a stable public release with up to 50 entries of each kind')
        release = page['releaseId']
        entries[kind] = page['items']
        for entry in entries[kind]:
            if entry['kind'] != kind or not SLUG.fullmatch(entry['slug']):
                raise ValueError('Invalid published entry identity')
    if not entries['facility']:
        raise ValueError('No published onsen facilities')
    pages = []
    for locale in LOCALES:
        base = f'/{locale}/onsen'
        list_query = urlencode(dict(query, release=release))
        pages.extend([
            (locale, base, base + '?' + list_query),
            (locale, base + '/coverage', base + '/coverage'),
            (locale, base + '/coverage/areas', base + '/coverage?kind=area'),
        ])
        for kind, rows in entries.items():
            for row in rows:
                path = f"{base}/{'facilities' if kind == 'facility' else 'areas'}/{row['slug']}"
                pages.append((locale, path, path + '?' + list_query))
    with ThreadPoolExecutor(max_workers=6) as pool:
        payloads = list(pool.map(lambda page: read_public(origin, page[2]), pages))
    css = set()
    rendered = {
        path[1:] + '.html': preview_html(data, locale, css)
        for (locale, path, _), data in zip(pages, payloads, strict=True)
    }
    for path in css:
        rendered[path[1:]] = read_public(origin, path)
    rendered['japan.svg'] = (root / 'public/japan.svg').read_bytes()
    rendered['robots.txt'] = b'User-agent: *\nDisallow: /\n'
    manifest = {'release': release, 'facilities': len(entries['facility']), 'areas': len(entries['area']),
                'locales': list(LOCALES), 'html_pages': len(pages)}
    rendered['snapshot.json'] = (json.dumps(manifest, indent=2) + '\n').encode()
    for filename, data in rendered.items():
        if any(x in data.lower() for x in (b'mail.google.com', b'127.0.0.1:', b'onsen_cursor_secret')):
            raise ValueError(f'Private reference in public snapshot: {filename}')
    output.mkdir()
    for filename, data in rendered.items():
        file = output / filename
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_bytes(data)
    print(json.dumps(manifest))


if __name__ == '__main__':
    main()
