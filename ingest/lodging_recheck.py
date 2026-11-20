"""Apply the reviewed Higashikawa and Biei lodging evidence to a loopback DB."""

import argparse
import json
from pathlib import Path
from urllib.parse import urlsplit

from ingest.takegawara import ImportBlocked, connect_local_db


ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "sources/higashikawa-biei-lodging-review-20261109.json"
SQL = ROOT / "supabase/seeds/higashikawa_biei_lodging_recheck.sql"
STATUS = {"open", "seasonal", "closed", "temporarily_closed", "unknown"}
ONSEN = {"on_site", "external_only", "not_on_site", "unknown"}


def text_field(value, limit):
    return isinstance(value, str) and value == value.strip() and 0 < len(value) <= limit and not any(
        ord(ch) < 32 for ch in value
    )


def source_url(value):
    if not text_field(value, 800) or any(ch.isspace() for ch in value):
        return False
    try:
        url = urlsplit(value)
        return bool(url.scheme == "https" and url.hostname and "." in url.hostname
                    and not url.username and not url.password and url.port in (None, 443))
    except ValueError:
        return False


def load_review(path=MANIFEST):
    with path.open("rb") as handle:
        body = handle.read(512 * 1024 + 1)
    if len(body) > 512 * 1024:
        raise ImportBlocked("Review manifest exceeds the approved size")
    data = json.loads(body.decode("utf-8"))
    if not isinstance(data, dict) or set(data) != {"target_rows", "decisions"}:
        raise ImportBlocked("Unexpected review manifest shape")
    rows, decisions = data["target_rows"], data["decisions"]
    if (not isinstance(rows, list) or len(rows) != 213
            or any(type(row) is not int or not 76 <= row <= 303 for row in rows)
            or len(set(rows)) != 213 or not isinstance(decisions, list)):
        raise ImportBlocked("The review must cover the 213 approved permit rows")
    common = {"row", "name", "identity_url", "operating", "operating_url", "onsen", "onsen_url", "note", "area_slug"}
    seen = set()
    for entry in decisions:
        if (not isinstance(entry, dict) or type(entry.get("row")) is not int
                or entry["row"] not in rows or entry["row"] in seen):
            raise ImportBlocked("Decision is outside the reviewed scope or repeats a permit")
        row = entry["row"]
        seen.add(row)
        if "name" not in entry:
            if (set(entry) != {"row", "reason", "url"} or not text_field(entry["reason"], 750)
                    or not source_url(entry["url"])):
                raise ImportBlocked(f"Invalid hold evidence for permit row {row}")
            continue
        if (set(entry) - common or not text_field(entry["name"], 220)
                or not text_field(entry.get("note"), 750) or not source_url(entry.get("identity_url"))
                or entry.get("operating") not in STATUS or entry.get("onsen") not in ONSEN
                or entry.get("area_slug") not in {None, "asahidake", "shirogane"}):
            raise ImportBlocked(f"Invalid facility evidence for permit row {row}")
        for field in ("operating", "onsen"):
            url = entry.get(field + "_url")
            if (url is not None and not source_url(url)) or (entry[field] != "unknown" and url is None):
                raise ImportBlocked(f"Missing or invalid {field} source for permit row {row}")
        if entry.get("area_slug") and entry["onsen"] != "on_site":
            raise ImportBlocked(f"Onsen area requires confirmed on-site evidence for permit row {row}")
    return data


def apply_review(connection, payload):
    from psycopg.types.json import Jsonb

    connection.execute("create temp table lodging_recheck_input (payload jsonb not null) on commit drop")
    connection.execute("insert into lodging_recheck_input values (%s)", (Jsonb(payload),))
    connection.execute(SQL.read_text(encoding="utf-8"))
    return connection.execute("""
        select municipality_code, imported_rows, linked_rows, linked_pending_rows, unlinked_pending_rows, excluded_rows
        from ingest.municipal_lodging_reconciliation
        where municipality_code in ('01458','01459') order by municipality_code
    """).fetchall()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Apply in one transaction to a loopback DB")
    args = parser.parse_args()
    try:
        payload = load_review()
        if args.apply:
            with connect_local_db() as connection, connection.transaction():
                rows = apply_review(connection, payload)
            print("municipality|imported|linked|linked_pending|unlinked_pending|excluded")
            for row in rows:
                print("|".join(map(str, row)))
        else:
            print(f"{len(payload['target_rows'])} reviewed permits; {len(payload['decisions'])} individual evidence records")
    except (ImportBlocked, OSError, ValueError) as exc:
        parser.exit(2, f"Lodging review blocked: {exc}\n")


if __name__ == "__main__":
    main()
