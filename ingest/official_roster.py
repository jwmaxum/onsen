"""Register a reviewed prefectural area roster without exposing the name data publicly."""
import argparse
import csv
import re
from datetime import date
from pathlib import Path

from ingest.takegawara import connect_local_db


def read_roster(path):
    if path.suffix.lower() not in {".csv", ".tsv"} or path.stat().st_size > 1024 * 1024:
        raise ValueError("Expected a reviewed CSV or TSV no larger than 1 MiB")
    with path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t" if path.suffix.lower() == ".tsv" else ",")
        fields = ["source_row", "name_ja", "municipality_ja"]
        if reader.fieldnames != fields:
            raise ValueError("Expected source_row, name_ja and municipality_ja columns in that order")
        rows = []
        for row in reader:
            if None in row or any(not row[field] or not row[field].strip() or len(row[field]) > 250 for field in fields):
                raise ValueError(f"Missing or invalid roster field on line {reader.line_num}")
            rows.append({field: row[field].strip() for field in fields})
    return rows


def main():
    from psycopg.types.json import Jsonb

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--file", required=True, type=Path)
    parser.add_argument("--prefecture", required=True)
    parser.add_argument("--fiscal-year", required=True, type=int)
    parser.add_argument("--as-of", required=True, type=date.fromisoformat)
    parser.add_argument("--coverage", choices=("complete", "partial"), required=True)
    parser.add_argument("--source-key", required=True)
    parser.add_argument("--source-sha256", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"0[1-9]|[1-3][0-9]|4[0-7]", args.prefecture):
        parser.error("--prefecture must be a two-digit prefecture code")
    if not re.fullmatch(r"[a-f0-9]{64}", args.source_sha256):
        parser.error("--source-sha256 must be the reviewed document SHA-256")
    try:
        rows = read_roster(args.file)
    except (ValueError, OSError) as exc:
        parser.error(str(exc))

    with connect_local_db() as connection, connection.transaction():
        docs = connection.execute("""
            select doc.id
            from ingest.source_documents doc
            join ingest.source_policy_versions policy on policy.id = doc.policy_version_id
            join ingest.source_registry source on source.id = policy.source_id
            where source.source_key = %s and doc.content_sha256 = %s
              and source.active and policy.revoked_at is null and policy.store_facts = 'allowed'
        """, (args.source_key, args.source_sha256)).fetchall()
        if len(docs) != 1:
            parser.error("Expected exactly one active document matching the reviewed source and SHA-256")
        connection.execute("""
            select ingest.register_official_area_roster(%s::char(2), %s::smallint, %s, %s, %s, %s)
        """, (args.prefecture, args.fiscal_year, args.as_of, docs[0][0], args.coverage, Jsonb(rows)))
        matches, areas = connection.execute("""
            select count(*), count(distinct source_row) from ingest.official_roster_candidate_matches
            where prefecture_code = %s and fiscal_year = %s
        """, (args.prefecture, args.fiscal_year)).fetchone()
    print(f"{args.prefecture}: {len(rows)} official roster rows, {matches} provisional links covering {areas} names")


if __name__ == "__main__":
    main()
