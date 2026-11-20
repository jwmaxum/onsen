"""Import facts visually transcribed from three reviewed Beppu analysis PDFs."""

import argparse
import hashlib
import os
import sys
import time
from dataclasses import dataclass
from datetime import date
from decimal import Decimal
from urllib.error import HTTPError, URLError
from urllib.request import HTTPRedirectHandler, ProxyHandler, Request, build_opener
from uuid import NAMESPACE_URL, uuid5

ORIGIN = "https://www.city.beppu.oita.jp"
ROBOTS_URL = f"{ORIGIN}/robots.txt"
TERMS_URL = f"{ORIGIN}/doc/sisei/df/henkaku/opendata/riyoukiyaku.pdf"
TERMS_SHA256 = "46e4a0694f9c8bd95e3395993a46868e36327edabd5a8976b56d3e2b12bac35b"
FACILITY_URL = f"{ORIGIN}/sisetu/shieionsen/detail4.html"
USER_AGENT = "OnsenCatalogBot/0.1"
SOURCE_KEY = "beppu_open_data"
POLICY_VERSION = 2
TRANSCRIPTION_VERSION = "takegawara-manual-v1"
SAMPLED_ON = date(2019, 2, 20)
ANALYZED_ON = date(2019, 3, 4)
ISSUED_ON = date(2019, 3, 7)
MAX_PDF_BYTES = 5_000_000


@dataclass(frozen=True)
class Sample:
    key: str
    bath_name: str
    sha256: str
    temperature: Decimal
    ph_onsite: Decimal
    ph_laboratory: Decimal
    quality: str
    quality_codes: tuple[str, ...]
    reservoir_label: str

    @property
    def url(self) -> str:
        return f"{ORIGIN}/doc/sisetu/sieionsen/04/bunseki_{self.key}.pdf"


MIXED_QUALITY = "ナトリウム・カルシウム・マグネシウム－塩化物・炭酸水素塩温泉"
SAMPLES = (
    Sample("men", "男湯", "15a2557c93c0182a766db7ec01474344a61bc6f9e0746c9e8285ca462d2a83a7",
           Decimal("48.8"), Decimal("7.5"), Decimal("7.5"), MIXED_QUALITY,
           ("chloride", "bicarbonate"), "貯湯枡"),
    Sample("women", "女湯", "5ff7abdc717a7a23c6b5548d029884dcd46b7a797738af41e82f56021bafcdcd",
           Decimal("48.9"), Decimal("7.7"), Decimal("7.8"), "ナトリウム－炭酸水素塩温泉",
           ("bicarbonate",), "貯湯枡"),
    Sample("suna", "砂湯", "9e2e4d99335bc0bfd69fac0c59106cffe039701fc93132674b799f76f8d62924",
           Decimal("52.1"), Decimal("7.3"), Decimal("7.4"), MIXED_QUALITY,
           ("chloride", "bicarbonate"), "貯湯槽"),
)


class ImportBlocked(Exception):
    """A source or local database prerequisite requires review."""


class NoRedirect(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def verify_pdf(opener, url, expected_hash):
    with opener.open(Request(url, headers={"User-Agent": USER_AGENT}), timeout=15) as response:
        if response.status != 200 or response.headers.get_content_type() != "application/pdf":
            raise ImportBlocked(f"Unexpected document response for {url}")
        content = response.read(MAX_PDF_BYTES + 1)
    if len(content) > MAX_PDF_BYTES or not content.startswith(b"%PDF-"):
        raise ImportBlocked(f"Unexpected PDF format or size for {url}")
    if hashlib.sha256(content).hexdigest() != expected_hash:
        raise ImportBlocked(f"Reviewed PDF has changed: {url}")


def verify_source():
    opener = build_opener(ProxyHandler({}), NoRedirect())
    try:
        time.sleep(2)
        try:
            with opener.open(Request(ROBOTS_URL, headers={"User-Agent": USER_AGENT}), timeout=15) as response:
                robots_status = response.status
        except HTTPError as error:
            with error:
                robots_status = error.code
        if robots_status != 404:
            raise ImportBlocked(f"robots.txt returned HTTP {robots_status}; the reviewed 404 policy no longer applies")
        # At most 30 requests per minute and no parallel requests to the publisher.
        for url, digest in [(TERMS_URL, TERMS_SHA256), *((sample.url, sample.sha256) for sample in SAMPLES)]:
            time.sleep(2)
            verify_pdf(opener, url, digest)
    except HTTPError as error:
        with error:
            raise ImportBlocked(f"Source request returned HTTP {error.code}") from None
    except (URLError, OSError):
        raise ImportBlocked("Source connection failed; no records were written") from None


def approved_policy(connection):
    rows = connection.execute("""
        select source.id, policy.id, allowed.source_url, allowed.approved_content_sha256
        from ingest.source_registry source
        join ingest.source_policy_versions policy on policy.source_id = source.id
        join ingest.source_policy_urls allowed on allowed.policy_version_id = policy.id
        where source.source_key = %s and source.active and policy.version = %s
          and policy.revoked_at is null and policy.terms_url = %s
          and policy.auto_fetch = 'allowed' and policy.robots_status = 'allowed'
          and policy.robots_http_status = 404 and policy.max_requests_per_minute >= 30
          and policy.archive_raw = 'denied' and policy.store_facts = 'allowed'
    """, (SOURCE_KEY, POLICY_VERSION, TERMS_URL)).fetchall()
    if {url: digest for _, _, url, digest in rows} != {sample.url: sample.sha256 for sample in SAMPLES}:
        raise ImportBlocked("Local DB lacks the active reviewed policy for all three file hashes")
    return rows[0][:2]


def stage_observations(connection, run_id, source_id, policy_id, sample):
    from psycopg.types.json import Jsonb

    connection.execute("""
        insert into ingest.source_documents (run_id, policy_version_id, source_url, content_sha256, parser_version)
        values (%s, %s, %s, %s, %s) on conflict (policy_version_id, source_url, content_sha256) do nothing
    """, (run_id, policy_id, sample.url, sample.sha256, TRANSCRIPTION_VERSION))
    document_id, = connection.execute("""
        select id from ingest.source_documents
        where policy_version_id = %s and source_url = %s and content_sha256 = %s
    """, (policy_id, sample.url, sample.sha256)).fetchone()
    record_id, = connection.execute("""
        insert into ingest.external_records (source_id, external_id) values (%s, %s)
        on conflict (source_id, external_id) do update set last_seen_at = greatest(ingest.external_records.last_seen_at, now())
        returning id
    """, (source_id, f"takegawara:{sample.key}")).fetchone()

    facts = (
        ("sampled_on", "p.1 III (ロ)", SAMPLED_ON.isoformat(), None),
        ("analyzed_on", "p.1 IV (ロ)", ANALYZED_ON.isoformat(), None),
        ("issued_on", "p.1 certificate date", ISSUED_ON.isoformat(), None),
        ("sample_medium", "p.1 II 採水場所", sample.reservoir_label, None),
        ("source_temp_celsius", "p.1 III (ハ)", float(sample.temperature), "°C"),
        ("ph_onsite", "p.1 III (ト), 25°C", float(sample.ph_onsite), "pH"),
        ("ph_laboratory", "p.1 IV (ホ), 25°C", float(sample.ph_laboratory), "pH"),
        ("quality_label_ja", "p.1 VI 泉質", sample.quality, None),
    )
    with connection.cursor() as cursor:
        cursor.executemany("""
            insert into ingest.field_observations (external_record_id, source_document_id, field_key,
                source_locator, value, unit, observed_at, value_state)
            values (%s, %s, %s, %s, %s, %s, now(), 'confirmed')
            on conflict (external_record_id, source_document_id, field_key, source_locator) do nothing
        """, [(record_id, document_id, key, locator, Jsonb(value), unit) for key, locator, value, unit in facts])
    return record_id, document_id


def store_analysis(connection, facility_id, sample, record_id, document_id):
    bath_id = uuid5(NAMESPACE_URL, sample.url + "#bath")
    spring_id = uuid5(NAMESPACE_URL, sample.url + "#spring")
    analysis_id = uuid5(NAMESPACE_URL, sample.url + "#" + sample.sha256)
    connection.execute("""
        insert into core.baths (id, facility_id, name_ja, setting, access_type)
        values (%s, %s, %s, 'unknown', 'unknown') on conflict (id) do nothing
    """, (bath_id, facility_id, sample.bath_name))
    connection.execute("""
        insert into core.catalog_entities (id, kind, prefecture_code, municipality_code, name_ja, review_state)
        values (%s, 'spring', '44', '44202', %s, 'in_review') on conflict (id) do nothing
    """, (spring_id, f"竹瓦温泉（{sample.bath_name}）"))
    connection.execute("insert into core.spring_sources (entity_id) values (%s) on conflict do nothing", (spring_id,))
    connection.execute("""
        insert into core.spring_usages (spring_id, facility_id, bath_id)
        values (%s, %s, %s) on conflict (spring_id, facility_id, bath_id, valid_from) do nothing
    """, (spring_id, facility_id, bath_id))
    linked = connection.execute("""
        update ingest.external_records set entity_id = %s where id = %s and (entity_id is null or entity_id = %s)
    """, (spring_id, record_id, spring_id)).rowcount
    if linked != 1:
        raise ImportBlocked(f"Existing source record for {sample.key} points to another entity")
    inserted = connection.execute("""
        insert into core.spring_analyses (id, spring_id, sample_kind, sampled_on, analyzed_on, ph_onsite,
            ph_laboratory, source_temp_celsius, quality_state, quality_label_ja, source_document_id)
        values (%s, %s, 'source', %s, %s, %s, %s, %s, 'classified', %s, %s) on conflict (id) do nothing
    """, (analysis_id, spring_id, SAMPLED_ON, ANALYZED_ON, sample.ph_onsite, sample.ph_laboratory,
          sample.temperature, sample.quality, document_id)).rowcount
    for code in sample.quality_codes:
        connection.execute("""
            insert into core.analysis_quality_codes (analysis_id, quality_code) values (%s, %s) on conflict do nothing
        """, (analysis_id, code))
    connection.execute("""
        insert into ingest.review_tasks (id, entity_id, reason) values (%s, %s, %s) on conflict (id) do nothing
    """, (analysis_id, spring_id, "Historical reservoir analysis. Verify attribution and suitability before publication."))
    return inserted


def import_verified(connection):
    from psycopg.types.json import Jsonb

    with connection.transaction():
        connection.execute("set local role onsen_ingestor")
        source_id, policy_id = approved_policy(connection)
        run_id, = connection.execute("""
            insert into ingest.harvest_runs (source_id, policy_version_id, mode, status)
            values (%s, %s, 'file', 'running') returning id
        """, (source_id, policy_id)).fetchone()
        evidence = [stage_observations(connection, run_id, source_id, policy_id, sample) for sample in SAMPLES]

        connection.execute("set local role onsen_reviewer")
        facility_id = uuid5(NAMESPACE_URL, FACILITY_URL)
        connection.execute("""
            insert into core.catalog_entities (id, kind, prefecture_code, municipality_code, name_ja, slug, review_state)
            values (%s, 'facility', '44', '44202', '竹瓦温泉', 'takegawara-onsen', 'in_review') on conflict (id) do nothing
        """, (facility_id,))
        connection.execute("""
            insert into core.facilities (entity_id, facility_type) values (%s, 'public_bath') on conflict do nothing
        """, (facility_id,))
        added = sum(store_analysis(connection, facility_id, sample, record_id, doc_id)
                    for sample, (record_id, doc_id) in zip(SAMPLES, evidence, strict=True))

        connection.execute("set local role onsen_ingestor")
        connection.execute("""
            update ingest.harvest_runs set status = 'succeeded', finished_at = clock_timestamp(), checkpoint = %s
            where id = %s
        """, (Jsonb({"verified_documents": [str(doc_id) for _, doc_id in evidence]}), run_id))
    return run_id, added


def connect_local_db():
    from psycopg import connect
    from psycopg.conninfo import conninfo_to_dict

    dsn = os.environ.get("ONSEN_LOCAL_DSN")
    if not dsn:
        raise ImportBlocked("Set ONSEN_LOCAL_DSN to a loopback PostgreSQL connection")
    options = conninfo_to_dict(dsn)
    host = options.get("host")
    if host not in {"127.0.0.1", "::1"} or options.get("hostaddr", host) != host or options.get("service"):
        raise ImportBlocked("Import requires an explicit loopback DB host and no connection service")

    return connect(dsn, hostaddr=host, connect_timeout=5, autocommit=True)


def apply_to_local_db():
    with connect_local_db() as connection:
        locked, = connection.execute("select pg_try_advisory_lock(179101, 2)").fetchone()
        if not locked:
            raise ImportBlocked("A Takegawara import is already running")
        with connection.transaction():
            connection.execute("set local role onsen_ingestor")
            approved_policy(connection)
        verify_source()
        run_id, added = import_verified(connection)
    print(f"Imported 3 verified samples into review. New analyses: {added}. Run: {run_id}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--apply", action="store_true", help="Recheck the source and import into a loopback DB")
    mode.add_argument("--dry-run", action="store_true", help="List the three reviewed files without network or DB writes")
    args = parser.parse_args()
    if not args.apply:
        for sample in SAMPLES:
            print(f"{sample.key} {sample.url} sha256={sample.sha256}")
        return 0
    try:
        import psycopg
    except ImportError:
        print("Install ingest/requirements.txt before applying", file=sys.stderr)
        return 1
    try:
        apply_to_local_db()
    except ImportBlocked as error:
        print(f"Import blocked: {error}", file=sys.stderr)
        return 1
    except psycopg.Error as error:
        print(f"Import failed at the database (SQLSTATE {error.sqlstate or 'unavailable'})", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
