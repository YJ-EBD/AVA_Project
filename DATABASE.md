# AVA Database

AVA uses PostgreSQL as the source of truth for the NodeBackend runtime.

## Core Tables

- `user_accounts`, `user_profiles`, `sessions`: identity, profile, presence, and login session state.
- `chat_rooms`, `chat_room_members`, `chat_message_records`, `chat_message_read_receipts`: realtime messenger rooms, messages, attachments, and unread counts.
- `chat_mention_notifications`, `notifications`, `mobile_push_events`: user-facing mention/app/mobile notification backlog.
- `app_update_releases`: optional persisted release metadata. File packages live under `NodeBackend/AppUpdates`.
- `app_settings`, `audit_logs`, `system_logs`: admin settings and operational logs.

## Calendar

- `calendar_categories`
- `calendar_events`
- `calendar_event_attendees`
- `calendar_event_reminders`
- `calendar_event_recurrences`
- `calendar_event_files`
- `calendar_event_notion_links`
- `calendar_event_chat_links`
- `calendar_event_azoom_links`

## AZOOM

- `azoom_voice_channels`: voice channel definitions.
- `azoom_voice_participants`: current voice participant state.
- `azoom_meeting_transcripts`: Notiva meeting transcript headers.
- `azoom_meeting_utterances`: ordered transcript utterances.

## AVA AI

- `ava_ai_messages`: per-user AI chat history.
- Workspace files are stored on disk under `NodeBackend/AiWorkspace` and are not committed.

## AVA_stock

The NodeBackend exposes the current AVA_stock API contract under `/api/ava-stock/**`. The lightweight Node implementation keeps the app contract active while a dedicated inventory persistence schema can be added behind the same endpoints.
