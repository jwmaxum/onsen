import type { Kind, Locale, Quality } from './catalog-query';

export type Entry = {
  release_id: string;
  entity_id: string;
  kind: Kind;
  prefecture_code: string;
  slug: string;
  name_ja: string;
  location_ja: string;
  latitude: number;
  longitude: number;
  facility_type: string | null;
  in_journey: boolean;
  public_source_url: string;
  verified_at: string;
  coordinate_accuracy: string;
  coordinate_source_url: string | null;
  coordinate_attribution: string | null;
  quality_codes: Quality[];
  day_admission_jpy: number | null;
};

export type CoverageRow = {
  prefecture_code: string;
  name_ja: string;
  name_en: string;
  status: 'published' | 'unresearched' | 'review_pending' | 'insufficient_data' | 'none_verified';
  registered_sources: number;
  candidates: number;
  reviewed: number;
  published: number;
  withdrawn: number;
  checked_on: string | null;
  gap_codes: ('inventory_pending' | 'optional_fields_pending' | 'other_rights_pending' | 'source_review_pending'
    | 'area_review_pending' | 'position_pending')[];
};

export type AreaInventoryProgress = {
  prefecture_code: string;
  fiscal_year: number | null;
  as_of: string | null;
  official_areas_with_lodging: number | null;
  source_url: string | null;
  attribution: string | null;
  designated_areas: number;
  discovery_records: number;
  reconciliation_gap: 'official_roster_unavailable' | 'official_roster_partial'
    | 'official_roster_reuse_pending' | 'official_roster_reconciled';
  registered_official_areas: number;
  official_areas_remaining: number | null;
};

export type CatalogPage = {
  items: Entry[];
  nextCursor: string | null;
  releaseId: string | null;
  asOf: string | null;
};

export type Analysis = {
  analysis_id: string;
  locale: Locale;
  sample_name: string;
  quality_name: string;
  sample_note: string;
  sampled_on: string;
  analyzed_on: string;
  source_temp_celsius: number;
  ph_onsite: number;
  ph_laboratory: number;
  source_publisher: string;
  source_url: string;
  source_terms_url: string;
  source_license: string;
  source_accessed_on: string;
  source_modified: boolean;
  source_attribution: string;
  source_transformation: string;
};

export type RouteLeg = {
  route_key: string;
  travel_mode: 'walk' | 'transit';
  verified_at: string;
  valid_until: string | null;
  duration_minutes: number | null;
  fare_jpy: number | null;
  transfers: number | null;
  route_source_url: string;
  seq: number;
  mode: 'walk' | 'bus';
  from_code: string;
  from_name_ja: string;
  to_code: string;
  to_name_ja: string;
  operator_name: string | null;
  service_name: string | null;
  leg_duration_minutes: number | null;
  leg_fare_jpy: number | null;
  reservation_required: boolean | null;
  leg_source_url: string;
};
