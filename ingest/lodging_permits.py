"""Import the reviewed Kamikawa health office lodging permit workbook."""

import argparse
from collections import Counter
from datetime import date, datetime
from hashlib import sha256
from io import BytesIO
from pathlib import Path

from ingest.takegawara import ImportBlocked, connect_local_db


SOURCE_KEY = "hokkaido_kamikawa_lodging_permits"
WORKBOOK_SHA256 = "163a0a1f6069ffb1cf14caae7a2bffb513aca369d096edf3daf7ae3175d4948f"
AS_OF = date(2026, 9, 30)
SHEET = "旅館業法"
HEADER = ("№", "営業区分", "施設名称", "施設所在地", "営業者名", "営業者住所（法人のみ）", "客室数", "許可年月日", "許可番号")
TARGETS = {"上川町": "01457", "東川町": "01458", "美瑛町": "01459"}
EXPECTED = {"01457": 36, "01458": 75, "01459": 153}
CATEGORIES = {"旅館・ホテル", "簡易宿所", "下宿"}
MAX_BYTES = 1024 * 1024


def required_text(value, maximum, row_number):
    if not isinstance(value, str) or not 1 <= len(value.strip()) <= maximum:
        raise ImportBlocked(f"Invalid facility or permit field at workbook row {row_number}")
    return value.strip()


def parse_permits(data: bytes):
    # Verify the reviewed bytes before passing the archive/XML to the XLSX library.
    if len(data) > MAX_BYTES or sha256(data).hexdigest() != WORKBOOK_SHA256:
        raise ImportBlocked("Workbook is not the reviewed SHA-256")
    from openpyxl import load_workbook

    rows = []
    workbook = load_workbook(BytesIO(data), read_only=True, keep_links=False, data_only=False)
    try:
        if SHEET not in workbook.sheetnames:
            raise ImportBlocked("Reviewed lodging sheet is missing")
        worksheet = workbook[SHEET]
        if (worksheet.max_row, worksheet.max_column) != (310, len(HEADER)):
            raise ImportBlocked("Unexpected lodging sheet dimensions")
        source = worksheet.iter_rows(min_row=3, values_only=True)
        if next(source, None) != HEADER:
            raise ImportBlocked("Unexpected lodging header")
        for row_number, cells in enumerate(source, 4):
            if cells[0] != row_number - 3:
                raise ImportBlocked(f"Missing or unexpected row marker at workbook row {row_number}")
            category, name, address = cells[1:4]
            address = required_text(address, 250, row_number)
            municipality = next((code for prefix, code in TARGETS.items() if address.startswith(prefix)), None)
            if municipality is None:
                continue
            # D is the premises address; E and F are applicant fields and are never emitted.
            rooms, issued, number = cells[6:9]
            if isinstance(issued, datetime):
                issued = issued.date()
            if (category not in CATEGORIES or type(rooms) is not int or rooms < 0
                    or not isinstance(issued, date) or issued > AS_OF):
                raise ImportBlocked(f"Invalid category, room count or issue date at workbook row {row_number}")
            rows.append({
                "municipality_code": municipality, "source_row": row_number,
                "permit_name": required_text(name, 250, row_number), "facility_address": address,
                "permit_category": category, "permit_rooms": rooms,
                "permit_issued_on": issued.isoformat(), "permit_number": required_text(number, 100, row_number),
            })
    finally:
        workbook.close()
    if Counter(row["municipality_code"] for row in rows) != EXPECTED:
        raise ImportBlocked("Extracted totals disagree with the three reviewed municipalities")
    return rows


def import_permits(connection, rows):
    from psycopg.types.json import Jsonb

    matches = connection.execute("""
        select d.id
        from ingest.source_documents d
        join ingest.source_policy_versions p on p.id = d.policy_version_id
        join ingest.source_registry s on s.id = p.source_id
        where s.source_key = %s and d.content_sha256 = %s
          and s.active and p.revoked_at is null and p.store_facts = 'allowed'
    """, (SOURCE_KEY, WORKBOOK_SHA256)).fetchall()
    if len(matches) != 1:
        raise ImportBlocked("Expected one active reviewed permit document; install the pilot seeds first")
    connection.execute(
        "select ingest.register_lodging_permits(%s, %s, %s, %s, %s)",
        (matches[0][0], AS_OF, list(EXPECTED), SHEET, Jsonb(rows)),
    )
    return connection.execute("""
        select municipality_code, imported_rows, linked_rows, linked_pending_rows, unlinked_pending_rows, excluded_rows
        from ingest.municipal_lodging_reconciliation
        where municipality_code::text = any(%s) and permit_as_of = %s
        order by municipality_code
    """, (list(EXPECTED), AS_OF)).fetchall()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--file", type=Path, required=True, help="Reviewed local XLSX, opened without archiving")
    parser.add_argument("--apply", action="store_true", help="Apply in one transaction to the loopback staging DB")
    args = parser.parse_args()
    try:
        if args.file.suffix.lower() != ".xlsx" or not args.file.is_file():
            raise ImportBlocked("Expected a reviewed XLSX file")
        with args.file.open("rb") as handle:
            rows = parse_permits(handle.read(MAX_BYTES + 1))
        if args.apply:
            with connect_local_db() as connection, connection.transaction():
                stats = import_permits(connection, rows)
            print("municipality|imported|linked|linked_pending|unlinked_pending|excluded")
            for row in stats:
                print("|".join(map(str, row)))
        else:
            for code, count in sorted(Counter(row["municipality_code"] for row in rows).items()):
                print(f"{code}: {count} reviewed workbook rows (preview)")
    except (OSError, ImportBlocked) as exc:
        parser.exit(2, f"Permit import blocked: {exc}\n")


if __name__ == "__main__":
    main()
