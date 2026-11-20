"""Load the curated lodging and Dormy directory observations into private review."""

import argparse
import hashlib
import json
import re
import sys
from datetime import date
from pathlib import Path
from urllib.parse import parse_qsl, urlsplit

from ingest.takegawara import connect_local_db


ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / 'sources'
FACILITY_FIELDS = {
    'key', 'prefecture_code', 'municipality_ja', 'area_ja', 'name_ja', 'name_ko',
    'facility_type', 'natural_onsen', 'lodging_evidence', 'address_ja', 'room_count',
    'natural_onsen_room_count', 'all_guest_rooms_with_natural_onsen', 'feature_ko',
    'check_before_booking_ko', 'access_ko', 'sources', 'supply_origin', 'flow_type',
    'spring_quality_ja', 'rental_open_air_bath_count', 'open_air_bath_count',
    'bath_area_count', 'bath_count_basis', 'season_2026', 'price_observations', 'permit_match',
}
DIRECTORY_FIELDS = {
    'directory_id', 'name_ja', 'website', 'region_ja', 'address_ja', 'pamphlet_url',
    'official_bath_title', 'bath_evidence', 'directory_status', 'opening_on',
}


def read_review(path):
    with path.open('rb') as handle:
        content = handle.read(1024 * 1024 + 1)
    if len(content) > 1024 * 1024:
        raise ValueError('Review input exceeds 1 MiB')
    data = json.loads(content)
    if data.get('schema_version') != 1:
        raise ValueError('Unsupported review format')
    date.fromisoformat(data['checked_on'])
    return data


def check_source(url):
    parts = urlsplit(url)
    if (parts.scheme != 'https' or not parts.hostname or parts.username or parts.password
            or parts.hostname in {'mail.google.com', 'maps.app.goo.gl', 'localhost'}
            or any(k.casefold() in {'token', 'password', 'key', 'api_key', 'access_token'}
                   for k, _ in parse_qsl(parts.query))):
        raise ValueError('Only public factual evidence links are accepted')


def packet(region, directory, yufuin):
    if len({a['checked_on'] for a in (region, directory, yufuin)}) != 1:
        raise ValueError('Review dates differ')
    rows = {}
    for entry in directory['entries']:
        identifier = entry['directory_id']
        key = 'dormy:' + identifier
        if not re.fullmatch(r'[a-z\d_-]+', identifier) or key in rows:
            raise ValueError('Invalid or repeated directory ID')
        for field in ('website', 'pamphlet_url'):
            if entry.get(field):
                check_source(entry[field])
        rows[key] = {'key': key, 'directory': {k: entry[k] for k in DIRECTORY_FIELDS if k in entry}}
    for facilities, in_yufuin in ((region['facilities'], False), (yufuin['facilities'], True)):
        for entry in facilities:
            identifier = entry['key']
            if not re.fullmatch(r'[a-z\d]+(?:-[a-z\d]+)*', identifier):
                raise ValueError('Invalid catalog candidate key')
            if not re.fullmatch(r'0[1-9]|[1-3][0-9]|4[0-7]', entry['prefecture_code']):
                raise ValueError('Invalid prefecture code')
            if entry['facility_type'] not in {'ryokan', 'hotel'} or not entry['sources']:
                raise ValueError('Missing accommodation evidence')
            for item in entry['sources']:
                check_source(item['url'])
            for price in entry.get('price_observations', []):
                check_source(price['source'])
            if in_yufuin:
                evidence = entry['permit_match']
                check_source(evidence['source'])
                if evidence['status'] != 'facility_name_and_site_reviewed' or evidence['source_row'] < 2:
                    raise ValueError('Yufuin draft requires a matched permit row')
            chain_id = entry.get('dormy_directory_id')
            key = f'dormy:{chain_id}' if chain_id else f'lodging:{identifier}'
            if chain_id and key not in rows:
                raise ValueError('Facility has no matching chain entry')
            row = rows.setdefault(key, {'key': key})
            if 'facility' in row:
                raise ValueError('Duplicate facility candidate')
            row.update(facility={k: entry[k] for k in FACILITY_FIELDS if k in entry}, yufuin=in_yufuin)
    area = yufuin['area']
    if (area['prefecture_code'], area['municipality_code'], area['name_ja']) != ('44', '44213', '由布院温泉'):
        raise ValueError('Unexpected Yufuin area identity')
    for url in area['sources']:
        check_source(url)
    return {'checked_on': region['checked_on'], 'area': area,
            'permit_source': yufuin['review']['permit_source'], 'entries': [rows[k] for k in sorted(rows)]}


def build_sql(args):
    data = packet(*(read_review(path) for path in (args.region, args.directory, args.yufuin)))
    content = json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode()
    template = (ROOT / 'supabase/seeds/lodging_catalog_batch.sql').read_text(encoding='utf-8')
    return template.replace('__BATCH_HEX__', content.hex()).replace('__BATCH_HASH__', hashlib.sha256(content).hexdigest()), data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--region', type=Path, default=DATA / 'ryokan-region-intake-20261120.json')
    parser.add_argument('--directory', type=Path, default=DATA / 'dormyinn-directory-review-20261120.json')
    parser.add_argument('--yufuin', type=Path, default=DATA / 'yufuin-lodging-review-20261120.json')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--apply', action='store_true', help='Use the configured loopback PostgreSQL connection')
    mode.add_argument('--emit-sql', action='store_true', help='Write the bounded batch statement to standard output')
    args = parser.parse_args()
    sql, data = build_sql(args)
    if args.emit_sql:
        sys.stdout.buffer.write((sql + '\n').encode('utf-8'))
        return
    if args.apply:
        with connect_local_db() as connection, connection.transaction():
            connection.execute(sql)
    print(f"{'Loaded' if args.apply else 'Validated'} {len(data['entries'])} distinct private lodging candidates.")


if __name__ == '__main__':
    main()
