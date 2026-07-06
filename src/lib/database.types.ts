export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  graphql_public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      graphql: {
        Args: {
          extensions?: Json
          operationName?: string
          query?: string
          variables?: Json
        }
        Returns: Json
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
  public: {
    Tables: {
      [_ in never]: never
    }
    Views: {
      [_ in never]: never
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
  supasheet: {
    Tables: {
      audit_logs: {
        Row: {
          changed_fields: string[] | null
          created_at: string
          created_by: string | null
          error_code: string | null
          error_message: string | null
          id: string
          is_error: boolean | null
          metadata: Json | null
          new_data: Json | null
          old_data: Json | null
          operation: string
          record_id: string | null
          role: Database["supasheet"]["Enums"]["app_role"] | null
          schema_name: string
          table_name: string
          user_type: string
        }
        Insert: {
          changed_fields?: string[] | null
          created_at?: string
          created_by?: string | null
          error_code?: string | null
          error_message?: string | null
          id?: string
          is_error?: boolean | null
          metadata?: Json | null
          new_data?: Json | null
          old_data?: Json | null
          operation: string
          record_id?: string | null
          role?: Database["supasheet"]["Enums"]["app_role"] | null
          schema_name: string
          table_name: string
          user_type?: string
        }
        Update: {
          changed_fields?: string[] | null
          created_at?: string
          created_by?: string | null
          error_code?: string | null
          error_message?: string | null
          id?: string
          is_error?: boolean | null
          metadata?: Json | null
          new_data?: Json | null
          old_data?: Json | null
          operation?: string
          record_id?: string | null
          role?: Database["supasheet"]["Enums"]["app_role"] | null
          schema_name?: string
          table_name?: string
          user_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "audit_logs_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      comments: {
        Row: {
          content: string
          created_at: string
          created_by: string | null
          id: string
          record_id: string
          schema_name: string
          table_name: string
          updated_at: string
        }
        Insert: {
          content: string
          created_at?: string
          created_by?: string | null
          id?: string
          record_id: string
          schema_name: string
          table_name: string
          updated_at?: string
        }
        Update: {
          content?: string
          created_at?: string
          created_by?: string | null
          id?: string
          record_id?: string
          schema_name?: string
          table_name?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "comments_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      configs: {
        Row: {
          description: string | null
          id: number
          is_public: boolean
          key: string
          value: Json | null
        }
        Insert: {
          description?: string | null
          id?: number
          is_public?: boolean
          key: string
          value?: Json | null
        }
        Update: {
          description?: string | null
          id?: number
          is_public?: boolean
          key?: string
          value?: Json | null
        }
        Relationships: []
      }
      notifications: {
        Row: {
          body: string | null
          created_at: string
          created_by: string | null
          id: string
          link: string | null
          metadata: Json
          title: string
          type: string
        }
        Insert: {
          body?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          link?: string | null
          metadata?: Json
          title: string
          type: string
        }
        Update: {
          body?: string | null
          created_at?: string
          created_by?: string | null
          id?: string
          link?: string | null
          metadata?: Json
          title?: string
          type?: string
        }
        Relationships: [
          {
            foreignKeyName: "notifications_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      role_permissions: {
        Row: {
          id: number
          permission: Database["supasheet"]["Enums"]["app_permission"]
          role: Database["supasheet"]["Enums"]["app_role"]
        }
        Insert: {
          id?: number
          permission: Database["supasheet"]["Enums"]["app_permission"]
          role: Database["supasheet"]["Enums"]["app_role"]
        }
        Update: {
          id?: number
          permission?: Database["supasheet"]["Enums"]["app_permission"]
          role?: Database["supasheet"]["Enums"]["app_role"]
        }
        Relationships: []
      }
      user_notifications: {
        Row: {
          archived_at: string | null
          created_at: string
          id: string
          notification_id: string
          read_at: string | null
          user_id: string
        }
        Insert: {
          archived_at?: string | null
          created_at?: string
          id?: string
          notification_id: string
          read_at?: string | null
          user_id: string
        }
        Update: {
          archived_at?: string | null
          created_at?: string
          id?: string
          notification_id?: string
          read_at?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_notifications_notification_id_fkey"
            columns: ["notification_id"]
            isOneToOne: false
            referencedRelation: "notifications"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_notifications_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      user_roles: {
        Row: {
          id: number
          role: Database["supasheet"]["Enums"]["app_role"]
          user_id: string
        }
        Insert: {
          id?: number
          role: Database["supasheet"]["Enums"]["app_role"]
          user_id: string
        }
        Update: {
          id?: number
          role?: Database["supasheet"]["Enums"]["app_role"]
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_roles_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "users"
            referencedColumns: ["id"]
          },
        ]
      }
      users: {
        Row: {
          created_at: string | null
          created_by: string | null
          email: string | null
          id: string
          name: string
          picture_url: string | null
          public_data: Json
          updated_at: string | null
          updated_by: string | null
        }
        Insert: {
          created_at?: string | null
          created_by?: string | null
          email?: string | null
          id?: string
          name: string
          picture_url?: string | null
          public_data?: Json
          updated_at?: string | null
          updated_by?: string | null
        }
        Update: {
          created_at?: string | null
          created_by?: string | null
          email?: string | null
          id?: string
          name?: string
          picture_url?: string | null
          public_data?: Json
          updated_at?: string | null
          updated_by?: string | null
        }
        Relationships: []
      }
    }
    Views: {
      columns: {
        Row: {
          actual_type: string | null
          check: string | null
          comment: string | null
          data_type: string | null
          default_value: string | null
          enums: Json | null
          format: string | null
          format_schema: string | null
          id: string | null
          identity_generation: string | null
          is_generated: boolean | null
          is_identity: boolean | null
          is_nullable: boolean | null
          is_unique: boolean | null
          is_updatable: boolean | null
          name: string | null
          ordinal_position: number | null
          schema: string | null
          table: string | null
          table_id: number | null
        }
        Relationships: []
      }
      materialized_views: {
        Row: {
          comment: string | null
          id: number | null
          is_populated: boolean | null
          name: string | null
          schema: string | null
        }
        Relationships: []
      }
      tables: {
        Row: {
          bytes: number | null
          comment: string | null
          dead_rows_estimate: number | null
          id: number | null
          live_rows_estimate: number | null
          name: string | null
          primary_keys: Json | null
          relationships: Json | null
          replica_identity: string | null
          rls_enabled: boolean | null
          rls_forced: boolean | null
          schema: string | null
          size: string | null
        }
        Relationships: []
      }
      views: {
        Row: {
          comment: string | null
          id: number | null
          is_updatable: boolean | null
          name: string | null
          schema: string | null
        }
        Relationships: []
      }
    }
    Functions: {
      apply_template: {
        Args: {
          p_schema: string
          p_target_table: string
          p_template_name: string
        }
        Returns: number
      }
      create_audit_log: {
        Args: {
          p_metadata?: Json
          p_new_data?: Json
          p_old_data?: Json
          p_operation: string
          p_record_id?: string
          p_schema_name: string
          p_table_name: string
        }
        Returns: string
      }
      create_notification: {
        Args: {
          p_body: string
          p_link?: string
          p_metadata?: Json
          p_title: string
          p_type: string
          p_user_ids: string[]
        }
        Returns: string
      }
      get_audit_logs: {
        Args: { p_record_id?: string; p_schema: string; p_table: string }
        Returns: {
          changed_fields: string[]
          created_at: string
          created_by: string
          created_by_email: string
          created_by_name: string
          created_by_picture_url: string
          error_code: string
          error_message: string
          id: string
          is_error: boolean
          metadata: Json
          new_data: Json
          old_data: Json
          operation: string
          record_id: string
          role: Database["supasheet"]["Enums"]["app_role"]
          schema_name: string
          table_name: string
          user_type: string
        }[]
      }
      get_charts: {
        Args: { p_schema?: string }
        Returns: {
          comment: string
          id: number
          is_updatable: boolean
          name: string
          schema: string
        }[]
      }
      get_columns: {
        Args: { action?: string; schema_name?: string; table_name?: string }
        Returns: {
          actual_type: string | null
          check: string | null
          comment: string | null
          data_type: string | null
          default_value: string | null
          enums: Json | null
          format: string | null
          format_schema: string | null
          id: string | null
          identity_generation: string | null
          is_generated: boolean | null
          is_identity: boolean | null
          is_nullable: boolean | null
          is_unique: boolean | null
          is_updatable: boolean | null
          name: string | null
          ordinal_position: number | null
          schema: string | null
          table: string | null
          table_id: number | null
        }[]
        SetofOptions: {
          from: "*"
          to: "columns"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      get_comments: {
        Args: { p_record_id: string; p_schema: string; p_table: string }
        Returns: {
          content: string
          created_at: string
          created_by: string
          created_by_email: string
          created_by_name: string
          created_by_picture_url: string
          id: string
          record_id: string
          schema_name: string
          table_name: string
          updated_at: string
        }[]
      }
      get_materialized_views: {
        Args: { action?: string; schema_name?: string; view_name?: string }
        Returns: {
          comment: string | null
          id: number | null
          is_populated: boolean | null
          name: string | null
          schema: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "materialized_views"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      get_nav_items: {
        Args: { schema_name?: string }
        Returns: {
          count: number
          type: string
        }[]
      }
      get_permissions: {
        Args: { schema_name?: string }
        Returns: {
          permission: Database["supasheet"]["Enums"]["app_permission"]
        }[]
      }
      get_privileges: {
        Args: { resource_name: string; schema_name: string }
        Returns: {
          privilege: string
        }[]
      }
      get_related_tables: {
        Args: { schema_name: string; table_name: string }
        Returns: {
          bytes: number
          comment: string
          dead_rows_estimate: number
          id: number
          live_rows_estimate: number
          name: string
          primary_keys: Json
          relationships: Json
          replica_identity: string
          rls_enabled: boolean
          rls_forced: boolean
          schema: string
          size: string
        }[]
      }
      get_reports: {
        Args: { p_schema?: string }
        Returns: {
          comment: string
          id: number
          is_updatable: boolean
          name: string
          schema: string
        }[]
      }
      get_schemas: {
        Args: never
        Returns: {
          schema: string
        }[]
      }
      get_storage_filename_as_uuid: { Args: { name: string }; Returns: string }
      get_tables: {
        Args: { action?: string; schema_name?: string; table_name?: string }
        Returns: {
          bytes: number | null
          comment: string | null
          dead_rows_estimate: number | null
          id: number | null
          live_rows_estimate: number | null
          name: string | null
          primary_keys: Json | null
          relationships: Json | null
          replica_identity: string | null
          rls_enabled: boolean | null
          rls_forced: boolean | null
          schema: string | null
          size: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "tables"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      get_templates: {
        Args: { p_schema?: string }
        Returns: {
          comment: string
          id: number
          is_updatable: boolean
          name: string
          schema: string
        }[]
      }
      get_users_with_permission: {
        Args: { p_permission: Database["supasheet"]["Enums"]["app_permission"] }
        Returns: string[]
      }
      get_users_with_role: {
        Args: { p_role: Database["supasheet"]["Enums"]["app_role"] }
        Returns: string[]
      }
      get_views: {
        Args: { action?: string; schema_name?: string; view_name?: string }
        Returns: {
          comment: string | null
          id: number | null
          is_updatable: boolean | null
          name: string | null
          schema: string | null
        }[]
        SetofOptions: {
          from: "*"
          to: "views"
          isOneToOne: false
          isSetofReturn: true
        }
      }
      get_widgets: {
        Args: { p_schema?: string }
        Returns: {
          comment: string
          id: number
          is_updatable: boolean
          name: string
          schema: string
        }[]
      }
      has_permission: {
        Args: {
          requested_permission: Database["supasheet"]["Enums"]["app_permission"]
        }
        Returns: boolean
      }
      has_role: {
        Args: { requested_role: Database["supasheet"]["Enums"]["app_role"] }
        Returns: boolean
      }
      mark_all_notifications_read: { Args: never; Returns: number }
      refresh_metadata: { Args: never; Returns: undefined }
      unread_notifications_count: { Args: never; Returns: number }
    }
    Enums: {
      app_permission:
        | "supasheet.users:select"
        | "supasheet.users:select_all"
        | "supasheet.users:update"
        | "supasheet.users:insert"
        | "supasheet.users:delete"
        | "supasheet.users:invite"
        | "supasheet.users:ban"
        | "supasheet.users:generate_link"
        | "supasheet.user_roles:select"
        | "supasheet.user_roles:select_all"
        | "supasheet.user_roles:insert"
        | "supasheet.user_roles:delete"
        | "supasheet.role_permissions:select"
        | "supasheet.role_permissions:select_all"
        | "supasheet.role_permissions:insert"
        | "supasheet.role_permissions:delete"
        | "supasheet.audit_logs:select"
        | "supasheet.audit_logs:select_all"
        | "supasheet.notifications:select"
        | "supasheet.user_notifications:select"
      app_role: "x-admin" | "admin" | "user"
    }
    CompositeTypes: {
      file_object: {
        name: string | null
        type: string | null
        size: number | null
        url: string | null
        last_modified: string | null
      }
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
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
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
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
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
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
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  graphql_public: {
    Enums: {},
  },
  public: {
    Enums: {},
  },
  supasheet: {
    Enums: {
      app_permission: [
        "supasheet.users:select",
        "supasheet.users:select_all",
        "supasheet.users:update",
        "supasheet.users:insert",
        "supasheet.users:delete",
        "supasheet.users:invite",
        "supasheet.users:ban",
        "supasheet.users:generate_link",
        "supasheet.user_roles:select",
        "supasheet.user_roles:select_all",
        "supasheet.user_roles:insert",
        "supasheet.user_roles:delete",
        "supasheet.role_permissions:select",
        "supasheet.role_permissions:select_all",
        "supasheet.role_permissions:insert",
        "supasheet.role_permissions:delete",
        "supasheet.audit_logs:select",
        "supasheet.audit_logs:select_all",
        "supasheet.notifications:select",
        "supasheet.user_notifications:select",
      ],
      app_role: ["x-admin", "admin", "user"],
    },
  },
} as const
