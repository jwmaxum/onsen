export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  api: {
    Tables: {
      published_entries: {
        Row: {
          entity_id: string
          facility_type: string | null
          in_journey: boolean
          kind: "area" | "facility" | "spring"
          latitude: number
          location_ja: string
          longitude: number
          name_ja: string
          prefecture_code: string
          public_source_url: string
          release_id: string
          slug: string
          verified_at: string
        }
        ComputedFields: never
        Insert: {
          entity_id: string
          facility_type?: string | null
          in_journey: boolean
          kind: "area" | "facility" | "spring"
          latitude: number
          location_ja: string
          longitude: number
          name_ja: string
          prefecture_code: string
          public_source_url: string
          release_id: string
          slug: string
          verified_at: string
        }
        Update: {
          entity_id?: string
          facility_type?: string | null
          in_journey?: boolean
          kind?: "area" | "facility" | "spring"
          latitude?: number
          location_ja?: string
          longitude?: number
          name_ja?: string
          prefecture_code?: string
          public_source_url?: string
          release_id?: string
          slug?: string
          verified_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "published_entries_prefecture_code_fkey"
            columns: ["prefecture_code"]
            isOneToOne: false
            referencedRelation: "area_inventory_progress"
            referencedColumns: ["prefecture_code"]
          },
          {
            foreignKeyName: "published_entries_prefecture_code_fkey"
            columns: ["prefecture_code"]
            isOneToOne: false
            referencedRelation: "prefecture_coverage"
            referencedColumns: ["prefecture_code"]
          },
          {
            foreignKeyName: "published_entries_release_id_fkey"
            columns: ["release_id"]
            isOneToOne: false
            referencedRelation: "releases"
            referencedColumns: ["id"]
          },
        ]
      }
      releases: {
        Row: {
          id: string
          published_at: string | null
          retained_until: string | null
          status: string
        }
        ComputedFields: never
        Insert: {
          id?: string
          published_at?: string | null
          retained_until?: string | null
          status?: string
        }
        Update: {
          id?: string
          published_at?: string | null
          retained_until?: string | null
          status?: string
        }
        Relationships: []
      }
    }
    Views: {
      area_inventory_progress: {
        Row: {
          as_of: string | null
          attribution: string | null
          designated_areas: number | null
          discovery_records: number | null
          fiscal_year: number | null
          official_areas_remaining: number | null
          official_areas_with_lodging: number | null
          prefecture_code: string
          reconciliation_gap: string | null
          registered_official_areas: number | null
          source_url: string | null
        }
        ComputedFields: never
        Relationships: []
      }
      prefecture_coverage: {
        Row: {
          candidates: number | null
          checked_on: string | null
          gap_codes: string[] | null
          kind: "area" | "facility" | "spring" | null
          name_en: string
          name_ja: string
          prefecture_code: string
          published: number | null
          registered_sources: number | null
          reviewed: number | null
          status: string | null
          withdrawn: number | null
        }
        ComputedFields: never
        Relationships: []
      }
      published_spring_analyses: {
        Row: {
          analysis_id: string
          analyzed_on: string | null
          facility_name: string
          facility_slug: string | null
          locale: string
          ph_laboratory: number | null
          ph_onsite: number | null
          published_at: string
          quality_codes: string[] | null
          quality_name: string
          sample_name: string
          sample_note: string
          sampled_on: string | null
          source_accessed_on: string | null
          source_attribution: string
          source_license: string | null
          source_modified: boolean | null
          source_publisher: string
          source_temp_celsius: number | null
          source_terms_url: string | null
          source_transformation: string
          source_url: string
        }
        ComputedFields: never
        Relationships: []
      }
      web_catalog_entries: {
        Row: {
          coordinate_accuracy: string | null
          coordinate_attribution: string | null
          coordinate_source_url: string | null
          day_admission_jpy: number | null
          entity_id: string | null
          facility_type: string | null
          in_journey: boolean | null
          kind: "area" | "facility" | "spring" | null
          latitude: number | null
          location_ja: string | null
          longitude: number | null
          name_ja: string | null
          prefecture_code: string | null
          public_source_url: string | null
          quality_codes: string[] | null
          release_id: string | null
          slug: string | null
          verified_at: string | null
        }
        ComputedFields: never
        Relationships: []
      }
      web_catalog_versions: {
        Row: {
          as_of: string | null
          release_id: string | null
          status: string | null
        }
        ComputedFields: never
        Relationships: []
      }
      web_pilot_entries: {
        Row: {
          coordinate_accuracy: string | null
          coordinate_attribution: string | null
          coordinate_source_url: string | null
          entity_id: string | null
          facility_type: string | null
          in_journey: boolean | null
          kind: "area" | "facility" | "spring" | null
          latitude: number | null
          location_ja: string | null
          longitude: number | null
          name_ja: string | null
          prefecture_code: string | null
          public_source_url: string | null
          release_id: string | null
          slug: string | null
          verified_at: string | null
        }
        ComputedFields: never
        Relationships: []
      }
      web_pilot_route_legs: {
        Row: {
          duration_minutes: number | null
          facility_slug: string | null
          fare_jpy: number | null
          from_code: string
          from_name_ja: string
          leg_duration_minutes: number | null
          leg_fare_jpy: number | null
          leg_source_url: string
          mode: string
          operator_name: string | null
          reservation_required: boolean | null
          route_key: string | null
          route_source_url: string
          seq: number
          service_name: string | null
          to_code: string
          to_name_ja: string
          transfers: number | null
          travel_mode: string
          valid_until: string | null
          verified_at: string | null
        }
        ComputedFields: never
        Relationships: []
      }
    }
    Functions: {
      [_ in never]: never
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "api">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  api: {
    Enums: {},
  },
} as const
