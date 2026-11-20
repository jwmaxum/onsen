create table ingest.analysis_publication_permissions (
    policy_version_id uuid not null,
    source_url text not null,
    content_sha256 text not null check (content_sha256 ~ '^[a-f0-9]{64}$'),
    reviewed_by text not null check (btrim(reviewed_by) <> ''),
    reviewed_at timestamptz not null,
    primary key (policy_version_id, source_url),
    foreign key (policy_version_id, source_url) references ingest.source_policy_urls (policy_version_id, source_url)
);

-- Approval applies to the reviewed analysis facts and their translations for these exact bytes.
insert into ingest.analysis_publication_permissions
    (policy_version_id, source_url, content_sha256, reviewed_by, reviewed_at)
select allowed.policy_version_id, allowed.source_url, allowed.approved_content_sha256,
    'phase3_source_review', now()
from ingest.source_policy_urls allowed
join ingest.source_policy_versions policy on policy.id = allowed.policy_version_id
join ingest.source_registry source on source.id = policy.source_id
where source.source_key = 'beppu_open_data' and policy.version = 2
  and allowed.source_url in (
    'https://www.city.beppu.oita.jp/doc/sisetu/sieionsen/04/bunseki_men.pdf',
    'https://www.city.beppu.oita.jp/doc/sisetu/sieionsen/04/bunseki_women.pdf',
    'https://www.city.beppu.oita.jp/doc/sisetu/sieionsen/04/bunseki_suna.pdf'
);

create table core.analysis_fact_reviews (
    analysis_id uuid primary key references core.spring_analyses,
    source_revision text not null check (source_revision ~ '^[a-f0-9]{64}$'),
    review_state core.review_state not null default 'draft',
    reviewed_by text,
    reviewed_at timestamptz,
    check (review_state <> 'approved' or (nullif(btrim(reviewed_by), '') is not null and reviewed_at is not null))
);

create table core.analysis_translations (
    analysis_id uuid not null references core.spring_analyses,
    locale text not null references core.locales check (locale in ('ja', 'ko', 'en', 'zh-Hans')),
    source_revision text not null check (source_revision ~ '^[a-f0-9]{64}$'),
    facility_name text not null check (btrim(facility_name) <> ''),
    sample_name text not null check (btrim(sample_name) <> ''),
    quality_name text not null check (btrim(quality_name) <> ''),
    sample_note text not null check (btrim(sample_note) <> ''),
    source_attribution text not null check (btrim(source_attribution) <> ''),
    source_transformation text not null check (btrim(source_transformation) <> ''),
    review_state core.review_state not null default 'draft',
    reviewed_by text,
    reviewed_at timestamptz,
    primary key (analysis_id, locale),
    check (review_state <> 'approved' or (nullif(btrim(reviewed_by), '') is not null and reviewed_at is not null))
);

create function core.reset_analysis_translation_review() returns trigger
language plpgsql set search_path = '' as $$
begin
    if row(new.source_revision, new.facility_name, new.sample_name, new.quality_name, new.sample_note,
           new.source_attribution, new.source_transformation)
       is distinct from
       row(old.source_revision, old.facility_name, old.sample_name, old.quality_name, old.sample_note,
           old.source_attribution, old.source_transformation) then
        new.review_state := 'draft';
        new.reviewed_at := null;
        new.reviewed_by := null;
    end if;
    return new;
end;
$$;
create trigger reset_analysis_translation_review before update on core.analysis_translations
    for each row execute function core.reset_analysis_translation_review();

create table core.analysis_publications (
    analysis_id uuid primary key references core.spring_analyses,
    source_revision text not null,
    review_revision text not null,
    published_at timestamptz not null,
    withdrawn_at timestamptz
);

create table core.analysis_publication_events (
    id uuid primary key default gen_random_uuid(),
    analysis_id uuid not null references core.spring_analyses,
    action text not null check (action in ('published', 'withdrawn')),
    review_revision text not null,
    actor text not null default session_user,
    recorded_at timestamptz not null default statement_timestamp()
);

create view core.analysis_source_facts as
select facts.*,
    encode(sha256(convert_to(to_jsonb(facts)::text, 'UTF8')), 'hex') as source_revision
from (
    select analysis.id as analysis_id, facility.slug as facility_slug, bath.name_ja as bath_name_ja,
        analysis.quality_label_ja, quality.codes as quality_codes,
        analysis.sampled_on, analysis.analyzed_on, analysis.source_temp_celsius,
        analysis.ph_onsite, analysis.ph_laboratory, doc.content_sha256,
        doc.source_url, source.publisher as source_publisher, policy.terms_url as source_terms_url,
        policy.license_label as source_license, (doc.fetched_at at time zone 'Asia/Tokyo')::date as source_accessed_on
    from core.spring_analyses analysis
    join core.catalog_entities spring on spring.id = analysis.spring_id
    join core.spring_usages usage on usage.spring_id = spring.id and usage.bath_id is not null
    join core.baths bath on bath.id = usage.bath_id and bath.facility_id = usage.facility_id
    join core.catalog_entities facility on facility.id = bath.facility_id
    join ingest.source_documents doc on doc.id = analysis.source_document_id
    join ingest.source_policy_versions policy on policy.id = doc.policy_version_id
    join ingest.source_registry source on source.id = policy.source_id
    join ingest.source_policy_urls allowed on allowed.policy_version_id = policy.id
        and allowed.source_url = doc.source_url and allowed.approved_content_sha256 = doc.content_sha256
    join ingest.analysis_publication_permissions rights on rights.policy_version_id = policy.id
        and rights.source_url = doc.source_url and rights.content_sha256 = doc.content_sha256
    cross join lateral (
        select array_agg(link.quality_code order by link.quality_code) as codes
        from core.analysis_quality_codes link where link.analysis_id = analysis.id
    ) quality
    where source.active and policy.revoked_at is null and policy.store_facts = 'allowed'
      and policy.publish_facts in ('allowed', 'conditional') and policy.translate_content in ('allowed', 'conditional')
      and policy.terms_url is not null and policy.license_label is not null
      and not spring.test_only and spring.review_state in ('in_review', 'approved')
      and not facility.test_only and facility.review_state in ('in_review', 'approved') and facility.slug is not null
      and analysis.sample_kind = 'source' and analysis.quality_state = 'classified'
      and analysis.quality_label_ja is not null and quality.codes is not null
      and analysis.sampled_on is not null and analysis.analyzed_on is not null
      and analysis.source_temp_celsius is not null and analysis.ph_onsite is not null and analysis.ph_laboratory is not null
      and (select count(*) from core.spring_usages candidate where candidate.spring_id = spring.id and candidate.bath_id is not null) = 1
      and exists (
          select 1 from ingest.field_observations observation
          join ingest.external_records record on record.id = observation.external_record_id
          where observation.source_document_id = doc.id and record.entity_id = spring.id
            and observation.field_key = 'sample_medium' and observation.value_state = 'confirmed'
            and observation.value in (to_jsonb('貯湯枡'::text), to_jsonb('貯湯槽'::text))
      )
) facts;

create view core.analysis_review_packets as
select facts.analysis_id, facts.source_revision,
    encode(sha256(convert_to(jsonb_build_array(
        fact_review.reviewed_by, extract(epoch from fact_review.reviewed_at),
        jsonb_agg(jsonb_build_array(translation.locale, translation.facility_name, translation.sample_name,
            translation.quality_name, translation.sample_note, translation.source_attribution,
            translation.source_transformation, translation.reviewed_by, extract(epoch from translation.reviewed_at))
            order by translation.locale)
    )::text, 'UTF8')), 'hex') as review_revision
from core.analysis_source_facts facts
join core.analysis_fact_reviews fact_review on fact_review.analysis_id = facts.analysis_id
    and fact_review.source_revision = facts.source_revision and fact_review.review_state = 'approved'
join core.analysis_translations translation on translation.analysis_id = facts.analysis_id
    and translation.source_revision = facts.source_revision and translation.review_state = 'approved'
group by facts.analysis_id, facts.source_revision, fact_review.reviewed_by, fact_review.reviewed_at
having count(*) = 4;

create function core.publish_spring_analysis(p_analysis_id uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
    packet core.analysis_review_packets%rowtype;
begin
    select * into packet from core.analysis_review_packets where analysis_id = p_analysis_id;
    if not found then
        raise check_violation using message = 'Current fact review, four reviewed translations and source rights are required';
    end if;

    insert into core.analysis_publications (analysis_id, source_revision, review_revision, published_at)
        values (packet.analysis_id, packet.source_revision, packet.review_revision, statement_timestamp())
    on conflict (analysis_id) do update set source_revision = excluded.source_revision,
        review_revision = excluded.review_revision, published_at = excluded.published_at, withdrawn_at = null
    where analysis_publications.review_revision is distinct from excluded.review_revision
       or analysis_publications.source_revision is distinct from excluded.source_revision
       or analysis_publications.withdrawn_at is not null;
    if not found then
        return false;
    end if;

    insert into core.analysis_publication_events (analysis_id, action, review_revision)
        values (p_analysis_id, 'published', packet.review_revision);
    return true;
end;
$$;

create function core.withdraw_spring_analysis(p_analysis_id uuid) returns boolean
language plpgsql security definer set search_path = '' as $$
declare
    withdrawn_revision text;
begin
    update core.analysis_publications set withdrawn_at = statement_timestamp()
        where analysis_id = p_analysis_id and withdrawn_at is null returning review_revision into withdrawn_revision;
    if not found then
        return false;
    end if;
    insert into core.analysis_publication_events (analysis_id, action, review_revision)
        values (p_analysis_id, 'withdrawn', withdrawn_revision);
    return true;
end;
$$;

-- This owner view is a deliberately narrow public projection. Its gates are evaluated on every read.
create view api.published_spring_analyses with (security_barrier = true) as
select facts.analysis_id, facts.facility_slug, translation.locale,
    translation.facility_name, translation.sample_name, translation.quality_name, translation.sample_note,
    facts.quality_codes, facts.sampled_on, facts.analyzed_on, facts.source_temp_celsius, facts.ph_onsite, facts.ph_laboratory,
    facts.source_publisher, facts.source_url, facts.source_terms_url, facts.source_license, facts.source_accessed_on,
    true as source_modified, translation.source_attribution, translation.source_transformation, publication.published_at
from core.analysis_source_facts facts
join core.analysis_review_packets packet on packet.analysis_id = facts.analysis_id
    and packet.source_revision = facts.source_revision
join core.analysis_publications publication on publication.analysis_id = facts.analysis_id
    and publication.source_revision = facts.source_revision and publication.review_revision = packet.review_revision
    and publication.withdrawn_at is null
join core.analysis_translations translation on translation.analysis_id = facts.analysis_id
    and translation.source_revision = facts.source_revision and translation.review_state = 'approved';

revoke all on ingest.analysis_publication_permissions, core.analysis_fact_reviews, core.analysis_translations,
    core.analysis_publications, core.analysis_publication_events, core.analysis_source_facts,
    core.analysis_review_packets, api.published_spring_analyses from public, anon, authenticated, service_role;
revoke execute on function core.reset_analysis_translation_review(), core.publish_spring_analysis(uuid),
    core.withdraw_spring_analysis(uuid) from public, anon, authenticated, service_role;
grant select on core.analysis_source_facts to onsen_reviewer;
grant select, insert, update on core.analysis_fact_reviews, core.analysis_translations to onsen_reviewer;
grant execute on function core.publish_spring_analysis(uuid), core.withdraw_spring_analysis(uuid) to onsen_publisher;
grant select on api.published_spring_analyses to anon, authenticated;
