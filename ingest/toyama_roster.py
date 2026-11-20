"""Validate Toyama's supplied FY2024 name roster and import reviewed facts."""

import argparse
import hashlib
import re
import unicodedata
from collections import Counter
from io import BytesIO
from pathlib import Path
from zipfile import ZipFile, BadZipFile

from ingest.takegawara import ImportBlocked, connect_local_db


SHA256 = "f901056a91f941ada014c8dbae0d6aaa0f52667bc154570d6d766ff1f734e00b"
ROOT = Path(__file__).resolve().parent.parent
SOURCE_KEY = "toyama_fy2024_supplied_area_roster"
EXPECTED = {
    "富山市": 13, "黒部市": 7, "朝日町": 2, "魚津市": 2, "上市町": 2, "立山町": 4,
    "高岡市": 3, "氷見市": 10, "砺波市": 6, "南砺市": 11, "小矢部市": 1,
}


def read_supplied_roster(path):
    from openpyxl import load_workbook

    with Path(path).open("rb") as handle:
        body = handle.read(1024 * 1024 + 1)
    if len(body) > 1024 * 1024 or hashlib.sha256(body).hexdigest() != SHA256:
        raise ImportBlocked("Toyama workbook does not match the reviewed SHA-256")
    with ZipFile(BytesIO(body)) as archive:
        if sum(entry.file_size for entry in archive.infolist()) > 3 * 1024 * 1024:
            raise ImportBlocked("Unexpected workbook archive size")
        if any("externalLinks" in name or "vbaProject" in name for name in archive.namelist()):
            raise ImportBlocked("Unexpected external links or workbook macros")
    workbook = load_workbook(BytesIO(body), read_only=True, data_only=False, keep_links=False)
    try:
        if workbook.sheetnames != ["Sheet2"]:
            raise ImportBlocked("Unexpected Toyama worksheet")
        sheet = workbook["Sheet2"]
        if (sheet.max_row, sheet.max_column) != (66, 3):
            raise ImportBlocked("Unexpected Toyama worksheet dimensions")
        if (sheet["B1"].value != "温泉利用状況報告書（宿泊施設のある温泉地名抜粋）"
                or sheet["C2"].value != "富山県令和７年３月末日現在"
                or sheet["B3"].value != "（源泉所在）\n市町村名" or sheet["C3"].value != "温泉地名"
                or sheet["C66"].value != "=COUNTA(C5:C65)"):
            raise ImportBlocked("Unexpected Toyama date, header or total range")
        result = []
        municipality = None
        for row_number, (_, city, name) in enumerate(
            sheet.iter_rows(min_row=5, max_row=65, max_col=3, values_only=True), 5
        ):
            if city is not None:
                if city not in EXPECTED:
                    raise ImportBlocked(f"Unknown source municipality on row {row_number}")
                municipality = city
            if municipality is None or not isinstance(name, str) or not name.strip() or name.startswith("="):
                raise ImportBlocked(f"Invalid source name on row {row_number}")
            cleaned = re.sub(r"\s+", " ", name).strip()
            result.append({
                "source_row": f"Sheet2!C{row_number}",
                "name_ja": cleaned,
                "municipality_ja": municipality,
            })
        if Counter(row["municipality_ja"] for row in result) != EXPECTED:
            raise ImportBlocked("Toyama municipality totals do not match the reviewed roster")
        keys = {(unicodedata.normalize("NFKC", row["name_ja"]), row["municipality_ja"]) for row in result}
        if len(result) != 61 or len(keys) != 61:
            raise ImportBlocked("Toyama roster must contain 61 distinct name/municipality pairs")
        return result
    finally:
        workbook.close()


def register_roster(connection, rows):
    from psycopg.types.json import Jsonb

    connection.execute((ROOT / "supabase/seeds/toyama_fy2024_roster_source.sql").read_text(encoding="utf-8"))
    documents = connection.execute("""
        select d.id from ingest.source_documents d
        join ingest.source_policy_versions p on p.id = d.policy_version_id
        join ingest.source_registry s on s.id = p.source_id
        where s.source_key = %s and d.content_sha256 = %s and s.active
          and p.revoked_at is null and p.store_facts = 'allowed' and p.publish_facts = 'allowed'
    """, (SOURCE_KEY, SHA256)).fetchall()
    if len(documents) != 1:
        raise ImportBlocked("Expected exactly one active reviewed Toyama document")
    document = documents[0][0]
    return connection.execute("""
        select ingest.register_official_area_roster('16', 2024::smallint, date '2025-03-31', %s, 'complete', %s)
    """, (document, Jsonb(rows))).fetchone()[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--file", type=Path, required=True, help="Provider's reviewed original XLSX")
    parser.add_argument("--apply", action="store_true", help="Import into a loopback DB in one transaction")
    args = parser.parse_args()
    try:
        rows = read_supplied_roster(args.file)
        if args.apply:
            with connect_local_db() as connection, connection.transaction():
                register_roster(connection, rows)
            print("Imported 61 reviewed FY2024 names; raw workbook and correspondence are not archived in DB")
        else:
            print("Validated 61 names in 11 source municipalities, as of 2025-03-31")
    except (ImportBlocked, OSError, ValueError, BadZipFile) as error:
        parser.exit(2, f"Toyama import blocked: {error}\n")


if __name__ == "__main__":
    main()
