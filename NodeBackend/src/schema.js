const { query } = require('./db');

async function ensureCoreSchema() {
  await query(`
    CREATE TABLE IF NOT EXISTS user_accounts (
      id uuid PRIMARY KEY,
      email varchar(160) NOT NULL UNIQUE,
      password_hash varchar(255) NOT NULL,
      display_name varchar(80) NOT NULL,
      role varchar(20) NOT NULL DEFAULT 'USER',
      enabled boolean NOT NULL DEFAULT true,
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS user_profiles (
      id uuid PRIMARY KEY,
      account_id uuid NOT NULL UNIQUE REFERENCES user_accounts(id) ON DELETE CASCADE,
      department varchar(80) NOT NULL DEFAULT 'Unknown',
      company_name varchar(80) DEFAULT 'ABBA-S',
      position varchar(80) DEFAULT 'Staff',
      nickname varchar(80),
      phone_number varchar(40),
      contact_email varchar(120),
      gender varchar(20),
      birth_date date,
      status varchar(32) NOT NULL DEFAULT 'offline',
      presence_updated_at timestamptz,
      avatar_color varchar(12) NOT NULL DEFAULT '#7AA06A',
      status_message varchar(120),
      avatar_image_url text,
      profile_background_color varchar(12),
      profile_background_image_url text
    );

    CREATE TABLE IF NOT EXISTS sessions (
      id uuid PRIMARY KEY,
      account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,
      session_id varchar(80) NOT NULL UNIQUE,
      remember_login boolean NOT NULL DEFAULT false,
      expires_at timestamptz NOT NULL,
      created_at timestamptz NOT NULL DEFAULT now(),
      last_seen_at timestamptz NOT NULL DEFAULT now(),
      invalidated_at timestamptz
    );

    CREATE TABLE IF NOT EXISTS auth_email_verification_codes (
      id uuid PRIMARY KEY,
      email varchar(160) NOT NULL,
      code_hash varchar(120) NOT NULL,
      created_at timestamptz NOT NULL DEFAULT now(),
      expires_at timestamptz NOT NULL,
      verified_at timestamptz,
      consumed_at timestamptz,
      attempts int NOT NULL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS user_chat_folder_settings (
      account_id uuid PRIMARY KEY REFERENCES user_accounts(id) ON DELETE CASCADE,
      folders_json text NOT NULL DEFAULT '[]',
      filter_order_json text DEFAULT '[]',
      quiet_room_ids_json text DEFAULT '[]',
      pinned_room_ids_json text DEFAULT '[]',
      updated_at timestamptz NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS chat_rooms (
      id uuid PRIMARY KEY,
      code varchar(80) NOT NULL UNIQUE,
      title varchar(120) NOT NULL,
      company_name varchar(80) DEFAULT 'ABBA-S',
      type varchar(20) NOT NULL,
      pinned_default boolean NOT NULL DEFAULT false,
      pinned_at timestamptz,
      last_message varchar(240) NOT NULL DEFAULT '',
      last_message_spoiler boolean NOT NULL DEFAULT false,
      avatar_image_url text,
      created_by_account_id uuid,
      last_message_at timestamptz NOT NULL DEFAULT now(),
      notice_message_id varchar(80),
      notice_sender_id varchar(80),
      notice_sender_name varchar(120),
      notice_content varchar(2000),
      notice_sent_at timestamptz,
      created_at timestamptz NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS chat_room_members (
      id uuid PRIMARY KEY,
      room_id uuid NOT NULL REFERENCES chat_rooms(id) ON DELETE CASCADE,
      account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,
      joined_at timestamptz DEFAULT now(),
      UNIQUE (room_id, account_id)
    );

    CREATE TABLE IF NOT EXISTS chat_message_records (
      id uuid PRIMARY KEY,
      room_code varchar(80) NOT NULL,
      sender_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,
      sender_name varchar(120) NOT NULL,
      content varchar(2000) NOT NULL,
      sent_at timestamptz NOT NULL DEFAULT now(),
      system_message boolean DEFAULT false,
      silent_message boolean DEFAULT false,
      spoiler_message boolean DEFAULT false,
      deleted_for_everyone boolean NOT NULL DEFAULT false,
      attachment_id varchar(80),
      attachment_group_id varchar(120),
      attachment_file_name varchar(512),
      attachment_content_type varchar(160),
      attachment_size bigint,
      attachment_stored_path varchar(1200),
      mention_user_ids varchar(2000),
      mention_display_names varchar(2000)
    );

    CREATE TABLE IF NOT EXISTS chat_message_read_receipts (
      id uuid PRIMARY KEY,
      message_id uuid NOT NULL REFERENCES chat_message_records(id) ON DELETE CASCADE,
      room_code varchar(80) NOT NULL,
      account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,
      read_at timestamptz NOT NULL DEFAULT now(),
      UNIQUE (message_id, account_id)
    );

    CREATE TABLE IF NOT EXISTS chat_mention_notifications (
      id uuid PRIMARY KEY,
      message_id uuid NOT NULL REFERENCES chat_message_records(id) ON DELETE CASCADE,
      mentioned_account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,
      room_code varchar(80) NOT NULL,
      mention_display_name varchar(120) NOT NULL,
      created_at timestamptz NOT NULL DEFAULT now(),
      checked_at timestamptz,
      UNIQUE (message_id, mentioned_account_id)
    );

    CREATE TABLE IF NOT EXISTS notifications (
      id uuid PRIMARY KEY,
      account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,
      type varchar(60) NOT NULL,
      title varchar(160) NOT NULL,
      body varchar(1000) NOT NULL,
      source_type varchar(80),
      source_id varchar(160),
      created_at timestamptz NOT NULL DEFAULT now(),
      read_at timestamptz
    );

    CREATE TABLE IF NOT EXISTS mobile_push_events (
      id uuid PRIMARY KEY,
      account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,
      type varchar(60) NOT NULL,
      title varchar(160) NOT NULL,
      body varchar(1000) NOT NULL,
      room_id varchar(120),
      room_title varchar(160),
      sender_name varchar(160),
      sender_nickname varchar(160),
      avatar_color varchar(32),
      source_type varchar(80),
      source_id varchar(160),
      data_json text,
      created_at timestamptz NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS app_update_releases (
      id uuid PRIMARY KEY,
      platform varchar(32) NOT NULL,
      version varchar(40) NOT NULL,
      file_name varchar(260) NOT NULL,
      required boolean NOT NULL DEFAULT false,
      release_notes text NOT NULL DEFAULT '',
      sha256 varchar(80),
      size_bytes bigint NOT NULL DEFAULT 0,
      package_available boolean NOT NULL DEFAULT false,
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now(),
      CONSTRAINT uk_app_update_release_platform_version UNIQUE (platform, version)
    );

    CREATE TABLE IF NOT EXISTS app_settings (
      setting_key varchar(120) PRIMARY KEY,
      setting_value text NOT NULL,
      description varchar(400),
      updated_by_account_id uuid,
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS audit_logs (
      id uuid PRIMARY KEY,
      actor_account_id uuid,
      actor_email varchar(160),
      action varchar(80) NOT NULL,
      resource_type varchar(80) NOT NULL,
      resource_id varchar(160),
      ip_address varchar(80),
      user_agent varchar(400),
      metadata text,
      created_at timestamptz NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS system_logs (
      id uuid PRIMARY KEY,
      request_id varchar(80) NOT NULL,
      account_id uuid,
      account_email varchar(160),
      method varchar(16) NOT NULL,
      path varchar(600) NOT NULL,
      query_string varchar(1000),
      status int NOT NULL,
      duration_ms int NOT NULL,
      ip_address varchar(80),
      user_agent varchar(400),
      error_message varchar(800),
      created_at timestamptz NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS calendar_categories (
      id uuid PRIMARY KEY,
      name varchar(80) NOT NULL,
      color varchar(30) NOT NULL,
      icon varchar(60),
      scope varchar(30) NOT NULL DEFAULT 'USER',
      owner_user_id uuid,
      is_default boolean NOT NULL DEFAULT false,
      sort_order int NOT NULL DEFAULT 0,
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS calendar_events (
      id uuid PRIMARY KEY,
      title varchar(200) NOT NULL,
      description text,
      start_at timestamptz NOT NULL,
      end_at timestamptz NOT NULL,
      all_day boolean NOT NULL DEFAULT false,
      location varchar(240),
      category_id uuid,
      color varchar(30),
      status varchar(30) NOT NULL DEFAULT 'SCHEDULED',
      meeting_status varchar(40) NOT NULL DEFAULT 'RESERVED',
      visibility varchar(30) NOT NULL DEFAULT 'ATTENDEES',
      detail_visibility varchar(30) NOT NULL DEFAULT 'FULL',
      owner_user_id uuid NOT NULL,
      created_by uuid NOT NULL,
      updated_by uuid,
      memo text,
      project_name varchar(160),
      team_id varchar(80),
      importance varchar(20) NOT NULL DEFAULT 'NORMAL',
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now(),
      deleted_at timestamptz
    );

    CREATE TABLE IF NOT EXISTS calendar_event_attendees (
      id uuid PRIMARY KEY,
      event_id uuid NOT NULL REFERENCES calendar_events(id) ON DELETE CASCADE,
      user_id uuid,
      display_name varchar(120) NOT NULL,
      department varchar(120),
      position varchar(120),
      email varchar(160),
      response_status varchar(30) NOT NULL DEFAULT 'PENDING',
      response_message varchar(500),
      responded_at timestamptz,
      created_at timestamptz NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS calendar_event_reminders (
      id uuid PRIMARY KEY,
      event_id uuid NOT NULL REFERENCES calendar_events(id) ON DELETE CASCADE,
      remind_before_minutes int NOT NULL,
      reminder_type varchar(30) NOT NULL DEFAULT 'IN_APP',
      target_type varchar(30) NOT NULL DEFAULT 'OWNER',
      target_id varchar(120),
      is_sent boolean NOT NULL DEFAULT false,
      sent_at timestamptz,
      created_at timestamptz NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS calendar_event_recurrences (
      id uuid PRIMARY KEY,
      event_id uuid NOT NULL UNIQUE REFERENCES calendar_events(id) ON DELETE CASCADE,
      recurrence_type varchar(30) NOT NULL DEFAULT 'NONE',
      interval_value int NOT NULL DEFAULT 1,
      days_of_week varchar(40),
      day_of_month int,
      end_type varchar(30) NOT NULL DEFAULT 'NEVER',
      until_date date,
      occurrence_count int,
      rrule text,
      timezone varchar(80) NOT NULL DEFAULT 'Asia/Seoul',
      created_at timestamptz NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS calendar_event_files (
      id uuid PRIMARY KEY,
      event_id uuid NOT NULL REFERENCES calendar_events(id) ON DELETE CASCADE,
      file_id varchar(120),
      file_name varchar(240) NOT NULL,
      file_path varchar(800),
      file_type varchar(80),
      file_size bigint,
      source_type varchar(30) NOT NULL DEFAULT 'NAS',
      linked_at timestamptz NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS calendar_event_notion_links (
      id uuid PRIMARY KEY,
      event_id uuid NOT NULL REFERENCES calendar_events(id) ON DELETE CASCADE,
      notion_page_id varchar(160),
      notion_database_id varchar(160),
      notion_title varchar(240) NOT NULL,
      notion_url varchar(1000),
      linked_at timestamptz NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS calendar_event_chat_links (
      id uuid PRIMARY KEY,
      event_id uuid NOT NULL REFERENCES calendar_events(id) ON DELETE CASCADE,
      chat_room_id varchar(120) NOT NULL,
      chat_room_name varchar(160),
      source_message_id varchar(120),
      source_message_preview varchar(1000),
      linked_at timestamptz NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS calendar_event_azoom_links (
      id uuid PRIMARY KEY,
      event_id uuid NOT NULL REFERENCES calendar_events(id) ON DELETE CASCADE,
      azoom_meeting_id varchar(160),
      azoom_room_id varchar(160),
      azoom_join_url varchar(1000),
      azoom_recording_id varchar(160),
      azoom_transcript_id varchar(160),
      azoom_minutes_id varchar(160),
      linked_at timestamptz NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS ava_ai_messages (
      id uuid PRIMARY KEY,
      conversation_id uuid NOT NULL,
      account_id uuid NOT NULL,
      company_name varchar(80) NOT NULL DEFAULT 'ABBA-S',
      role varchar(20) NOT NULL,
      content text NOT NULL,
      model varchar(80),
      created_at timestamptz NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS azoom_voice_channels (
      id uuid PRIMARY KEY,
      company_name varchar(80) NOT NULL DEFAULT 'ABBA-S',
      name varchar(120) NOT NULL,
      room_name varchar(160) NOT NULL UNIQUE,
      started_at timestamptz,
      access_mode varchar(30) NOT NULL DEFAULT 'ALL',
      allowed_departments_json text NOT NULL DEFAULT '[]',
      archived_at timestamptz,
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS azoom_voice_participants (
      id uuid PRIMARY KEY,
      channel_id uuid NOT NULL REFERENCES azoom_voice_channels(id) ON DELETE CASCADE,
      account_id uuid NOT NULL REFERENCES user_accounts(id) ON DELETE CASCADE,
      muted boolean NOT NULL DEFAULT false,
      deafened boolean NOT NULL DEFAULT false,
      camera_enabled boolean NOT NULL DEFAULT false,
      screen_sharing boolean NOT NULL DEFAULT false,
      joined_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now(),
      UNIQUE (channel_id, account_id)
    );

    CREATE TABLE IF NOT EXISTS azoom_meeting_transcripts (
      id uuid PRIMARY KEY,
      company_name varchar(80) NOT NULL DEFAULT 'ABBA-S',
      company_slug varchar(120) NOT NULL DEFAULT 'abba-s',
      channel_id uuid,
      channel_name varchar(120) NOT NULL,
      room_name varchar(160) NOT NULL,
      kind varchar(30) NOT NULL DEFAULT 'REALTIME',
      status varchar(30) NOT NULL DEFAULT 'READY',
      title_timestamp varchar(80) NOT NULL,
      audio_file_path text,
      started_at timestamptz NOT NULL DEFAULT now(),
      ended_at timestamptz,
      created_by uuid,
      created_at timestamptz NOT NULL DEFAULT now(),
      updated_at timestamptz NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS azoom_meeting_utterances (
      id uuid PRIMARY KEY,
      transcript_id uuid NOT NULL REFERENCES azoom_meeting_transcripts(id) ON DELETE CASCADE,
      sequence_no int NOT NULL,
      speaker_user_id uuid,
      speaker_name varchar(160) NOT NULL DEFAULT '',
      speaker_email varchar(160) NOT NULL DEFAULT '',
      content text NOT NULL,
      started_at timestamptz,
      ended_at timestamptz,
      created_at timestamptz NOT NULL DEFAULT now()
    );

    CREATE INDEX IF NOT EXISTS idx_sessions_account_active ON sessions(account_id, expires_at, invalidated_at);
    CREATE INDEX IF NOT EXISTS idx_auth_email_verification_email_created ON auth_email_verification_codes(email, created_at);
    CREATE INDEX IF NOT EXISTS idx_chat_message_records_room_sent_at ON chat_message_records(room_code, sent_at);
    CREATE INDEX IF NOT EXISTS idx_chat_message_records_room_sender_sent ON chat_message_records(room_code, sender_id, sent_at);
    CREATE INDEX IF NOT EXISTS idx_chat_room_members_account_room ON chat_room_members(account_id, room_id);
    CREATE INDEX IF NOT EXISTS idx_chat_room_members_room_joined ON chat_room_members(room_id, joined_at);
    CREATE INDEX IF NOT EXISTS idx_chat_read_receipts_room ON chat_message_read_receipts(room_code);
    CREATE INDEX IF NOT EXISTS idx_chat_read_receipts_account ON chat_message_read_receipts(account_id);
    CREATE INDEX IF NOT EXISTS idx_chat_mentions_account_checked_created ON chat_mention_notifications(mentioned_account_id, checked_at, created_at);
    CREATE INDEX IF NOT EXISTS idx_chat_mentions_room_account_checked ON chat_mention_notifications(room_code, mentioned_account_id, checked_at);
    CREATE INDEX IF NOT EXISTS idx_notifications_account_created ON notifications(account_id, created_at);
    CREATE INDEX IF NOT EXISTS idx_notifications_account_read ON notifications(account_id, read_at);
    CREATE INDEX IF NOT EXISTS idx_calendar_events_start ON calendar_events(start_at, end_at);
    CREATE INDEX IF NOT EXISTS idx_azoom_voice_channels_company ON azoom_voice_channels(company_name, archived_at);
    CREATE INDEX IF NOT EXISTS idx_azoom_participants_channel ON azoom_voice_participants(channel_id);
    CREATE INDEX IF NOT EXISTS idx_azoom_transcripts_company_created ON azoom_meeting_transcripts(company_name, created_at);

    ALTER TABLE ava_ai_messages ADD COLUMN IF NOT EXISTS model varchar(80);
  `);
}

module.exports = {
  ensureCoreSchema
};
