export const entryColumns = 'release_id,entity_id,kind,prefecture_code,slug,name_ja,location_ja,latitude,longitude,facility_type,in_journey,public_source_url,verified_at,coordinate_accuracy,quality_codes,day_admission_jpy,coordinate_source_url,coordinate_attribution';
export const analysisColumns = 'analysis_id,locale,sample_name,quality_name,sample_note,sampled_on,analyzed_on,source_temp_celsius,ph_onsite,ph_laboratory,source_publisher,source_url,source_terms_url,source_license,source_accessed_on,source_modified,source_attribution,source_transformation';
export const legColumns = 'route_key,travel_mode,verified_at,valid_until,duration_minutes,fare_jpy,transfers,route_source_url,seq,mode,from_code,from_name_ja,to_code,to_name_ja,operator_name,service_name,leg_duration_minutes,leg_fare_jpy,reservation_required,leg_source_url';
export const coverageColumns = 'prefecture_code,name_ja,name_en,status,registered_sources,candidates,reviewed,published,withdrawn,checked_on,gap_codes';
export const inventoryColumns = 'prefecture_code,fiscal_year,as_of,official_areas_with_lodging,source_url,attribution,designated_areas,discovery_records,reconciliation_gap,registered_official_areas,official_areas_remaining';
export const firebaseCatalogPath = '/onsen_public/v1.json';
export const maxCatalogBytes = 2 * 1024 * 1024;
