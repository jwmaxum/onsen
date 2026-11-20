-- Names counted in the Ministry denominator are stored separately from discovery candidates and map entries.
create table ingest.official_area_roster_source_approvals (
    prefecture_code char(2) not null references core.prefectures,
    fiscal_year smallint not null check (fiscal_year >= 1900),
    as_of date not null,
    source_document_id uuid not null references ingest.source_documents,
    coverage text not null check (coverage in ('complete', 'partial')),
    evidence_note text not null check (btrim(evidence_note) <> ''),
    primary key (prefecture_code, fiscal_year, source_document_id)
);

create table ingest.official_area_rosters (
    id uuid primary key default gen_random_uuid(),
    prefecture_code char(2) not null,
    fiscal_year smallint not null,
    benchmark_unit text generated always as ('area_with_lodging'::text) stored,
    source_document_id uuid not null references ingest.source_documents,
    coverage text not null check (coverage in ('complete', 'partial')),
    input_sha256 text not null check (input_sha256 ~ '^[a-f0-9]{64}$'),
    reviewed_at timestamptz not null,
    unique (prefecture_code, fiscal_year),
    foreign key (prefecture_code, fiscal_year, source_document_id)
        references ingest.official_area_roster_source_approvals,
    foreign key (prefecture_code, fiscal_year, benchmark_unit)
        references core.official_coverage_benchmarks (prefecture_code, fiscal_year, unit)
);

create table ingest.official_area_roster_entries (
    roster_id uuid not null references ingest.official_area_rosters,
    source_row text not null check (btrim(source_row) <> ''),
    name_ja text not null check (btrim(name_ja) <> ''),
    municipality_ja text not null check (btrim(municipality_ja) <> ''),
    primary key (roster_id, source_row)
);

create function ingest.register_official_area_roster(
    p_prefecture char(2), p_year smallint, p_as_of date, p_document uuid, p_coverage text, p_rows jsonb
) returns uuid language plpgsql set search_path = '' as $$
declare
    benchmark core.official_coverage_benchmarks%rowtype;
    existing ingest.official_area_rosters%rowtype;
    roster_id uuid;
    input_hash text;
    names integer;
begin
    select * into strict benchmark from core.official_coverage_benchmarks baseline
    where baseline.prefecture_code = p_prefecture and baseline.fiscal_year = p_year and baseline.unit = 'area_with_lodging'
    for update;
    if p_as_of is distinct from benchmark.as_of or p_coverage is null or p_coverage not in ('complete', 'partial')
        or jsonb_typeof(p_rows) is distinct from 'array' then
        raise check_violation using message = 'Roster scope must match the benchmark snapshot';
    end if;
    names := jsonb_array_length(p_rows);
    if names = 0 or (p_coverage = 'complete' and names <> benchmark.counted)
        or (p_coverage = 'partial' and names >= benchmark.counted) then
        raise check_violation using message = 'Roster name count disagrees with its declared coverage';
    end if;
    if exists (
        select 1 from jsonb_to_recordset(p_rows) as input(name_ja text, municipality_ja text)
        group by regexp_replace(normalize(input.name_ja, NFKC), '[[:space:]]+', '', 'g'),
            regexp_replace(normalize(input.municipality_ja, NFKC), '[[:space:]]+', '', 'g')
        having count(*) > 1
    ) then
        raise check_violation using message = 'Roster contains duplicate area names in the same municipality';
    end if;
    if not exists (
        select 1 from ingest.source_documents doc
        join ingest.source_policy_versions policy on policy.id = doc.policy_version_id
        join ingest.source_registry source on source.id = policy.source_id
        join ingest.source_policy_urls allowed on allowed.policy_version_id = policy.id and allowed.source_url = doc.source_url
        join ingest.official_area_roster_source_approvals approval on approval.source_document_id = doc.id
            and approval.prefecture_code = p_prefecture and approval.fiscal_year = p_year
            and approval.as_of = p_as_of and approval.coverage = p_coverage
        where doc.id = p_document and (source.prefecture_code is null or source.prefecture_code = p_prefecture)
          and source.active and policy.revoked_at is null and policy.store_facts = 'allowed'
          and doc.content_sha256 is not null
    ) then
        raise check_violation using message = 'Roster requires a reviewed, hash-pinned source with factual storage permission';
    end if;

    input_hash := encode(sha256(convert_to(p_rows::text, 'UTF8')), 'hex');
    select * into existing from ingest.official_area_rosters stored
    where stored.prefecture_code = p_prefecture and stored.fiscal_year = p_year;
    if found then
        if existing.source_document_id = p_document and existing.input_sha256 = input_hash and existing.coverage = p_coverage then
            return existing.id;
        end if;
        raise unique_violation using message = 'A different roster already exists; review the correction before replacing it';
    end if;

    insert into ingest.official_area_rosters (prefecture_code, fiscal_year, source_document_id, coverage, input_sha256, reviewed_at)
    values (p_prefecture, p_year, p_document, p_coverage, input_hash, statement_timestamp())
    returning id into roster_id;
    insert into ingest.official_area_roster_entries
    select roster_id, btrim(input.source_row), btrim(input.name_ja), btrim(input.municipality_ja)
    from jsonb_to_recordset(p_rows) as input(source_row text, name_ja text, municipality_ja text);
    return roster_id;
end;
$$;

-- Name suggestions remain private and do not mutate or merge any candidate or public area.
create view ingest.official_roster_candidate_matches as
select roster.prefecture_code, roster.fiscal_year, entry.source_row, entry.name_ja,
    entry.municipality_ja, candidate.source_document_id, candidate.external_id, candidate.reference_url,
    case when keys.candidate_name = keys.roster_name then 'normalized_exact' else 'onsen_suffix' end as match_basis
from ingest.official_area_rosters roster
join ingest.official_area_roster_entries entry on entry.roster_id = roster.id
join ingest.area_inventory_candidates candidate on candidate.prefecture_code = roster.prefecture_code
cross join lateral (
    select regexp_replace(normalize(candidate.name_ja, NFKC), '[[:space:]]+', '', 'g') as candidate_name,
        regexp_replace(normalize(entry.name_ja, NFKC), '[[:space:]]+', '', 'g') as roster_name
) keys
where keys.candidate_name = keys.roster_name
    or (length(regexp_replace(keys.roster_name, '温泉$', '')) > 0
        and regexp_replace(keys.candidate_name, '温泉$', '') = regexp_replace(keys.roster_name, '温泉$', ''));

create or replace view api.area_inventory_progress with (security_barrier = true) as
with live_docs as (
    select doc.id, doc.source_url, policy.attribution
    from ingest.source_documents doc
    join ingest.source_policy_versions policy on policy.id = doc.policy_version_id
    join ingest.source_registry source on source.id = policy.source_id
    join ingest.source_policy_urls allowed on allowed.policy_version_id = policy.id and allowed.source_url = doc.source_url
    where source.active and policy.revoked_at is null and policy.publish_facts = 'allowed'
), latest_benchmark as (
    select distinct on (bench.prefecture_code) bench.prefecture_code, bench.fiscal_year, bench.as_of,
        bench.counted, doc.source_url, doc.attribution
    from core.official_coverage_benchmarks bench
    join live_docs doc on doc.id = bench.source_document_id
    where bench.unit = 'area_with_lodging'
    order by bench.prefecture_code, bench.fiscal_year desc
), designated as (
    select jurisdiction.prefecture_code, count(*)::integer as counted
    from core.national_area_designations designation
    join core.national_area_designation_jurisdictions jurisdiction on jurisdiction.entity_id = designation.entity_id
    join core.catalog_entities area on area.id = designation.entity_id
    join live_docs doc on doc.id = designation.source_document_id
    where not area.test_only and area.review_state <> 'withdrawn'
    group by jurisdiction.prefecture_code
), candidates as (
    select candidate.prefecture_code, count(*)::integer as counted
    from ingest.area_inventory_candidates candidate
    join live_docs doc on doc.id = candidate.source_document_id
    group by candidate.prefecture_code
), roster_counts as (
    select roster.prefecture_code, roster.fiscal_year, roster.coverage, policy.publish_facts, count(*)::integer as registered
    from ingest.official_area_rosters roster
    join ingest.official_area_roster_entries entry on entry.roster_id = roster.id
    join ingest.source_documents doc on doc.id = roster.source_document_id
    join ingest.source_policy_versions policy on policy.id = doc.policy_version_id
    join ingest.source_registry source on source.id = policy.source_id
    join ingest.source_policy_urls allowed on allowed.policy_version_id = policy.id and allowed.source_url = doc.source_url
    where source.active and policy.revoked_at is null and policy.store_facts = 'allowed'
    group by roster.prefecture_code, roster.fiscal_year, roster.coverage, policy.publish_facts
)
select prefecture.code as prefecture_code, benchmark.fiscal_year, benchmark.as_of,
    benchmark.counted as official_areas_with_lodging, benchmark.source_url, benchmark.attribution,
    coalesce(designated.counted, 0) as designated_areas,
    coalesce(candidates.counted, 0) as discovery_records,
    case
        when roster.registered is null then 'official_roster_unavailable'
        when roster.coverage = 'partial' or roster.registered <> benchmark.counted then 'official_roster_partial'
        when roster.publish_facts <> 'allowed' then 'official_roster_reuse_pending'
        else 'official_roster_reconciled'
    end as reconciliation_gap,
    coalesce(roster.registered, 0) as registered_official_areas,
    case when benchmark.counted is not null then greatest(benchmark.counted - coalesce(roster.registered, 0), 0) end
        as official_areas_remaining
from core.prefectures prefecture
left join latest_benchmark benchmark on benchmark.prefecture_code = prefecture.code
left join designated on designated.prefecture_code = prefecture.code
left join candidates on candidates.prefecture_code = prefecture.code
left join roster_counts roster on roster.prefecture_code = prefecture.code and roster.fiscal_year = benchmark.fiscal_year;

revoke all on ingest.official_area_roster_source_approvals, ingest.official_area_rosters, ingest.official_area_roster_entries,
    ingest.official_roster_candidate_matches from public, anon, authenticated, service_role;
revoke execute on function ingest.register_official_area_roster(character, smallint, date, uuid, text, jsonb)
    from public, anon, authenticated, service_role;
grant select on ingest.official_area_roster_source_approvals, ingest.official_area_rosters, ingest.official_area_roster_entries,
    ingest.official_roster_candidate_matches to onsen_reviewer;
