# AVA Database

The current backend uses Hibernate `ddl-auto=update`. These tables are implemented by JPA entities unless noted.

## Auth And Users

- `user_accounts`
  - account id, email, password hash, display name, role, enabled flag, timestamps
- `user_profiles`
  - one profile per account, company, department, position, nickname, phone, birth date, presence, avatar/profile images
- `sessions`
  - persisted login sessions, session id, account id, remember flag, expiry, invalidation, last seen
- `roles`
  - seeded role catalog: `ADMIN`, `USER`
- `permissions`
  - seeded permission catalog for future fine-grained permissions
- `user_roles`
  - assignment table for future multi-role expansion
- `company_blocked_employees`
  - company-level employee block list
- `user_chat_folder_settings`
  - per-user folder/filter/quiet-room settings

## Normal Messenger

- `chat_rooms`
  - normal messenger room metadata and notice state
- `chat_room_members`
  - room membership
- `chat_message_records`
  - persisted relational message records and attachment metadata
- `chat_message_read_receipts`
  - message read receipts
- `chat_talk_drawer_items`
  - media/file drawer items
- MongoDB `chat_messages`
  - optional message document mirror/history path

## AZOOM

- `azooms`
  - company-scoped AZOOM workspace record
- `azoom_channels`
  - persisted text/voice channels, sort order, archive state
- `azoom_members`
  - workspace members and AZOOM roles: `OWNER`, `MANAGER`, `MEMBER`
- `azoom_chat_messages`
  - AZOOM-only text messages by company slug and channel id
- `azoom_voice_meeting_transcripts`
  - Notiva AI voice-channel transcript headers, company/workspace, voice channel, room name, `REALTIME` or `BATCH_AUDIO`, `yyyy:MM:dd (E) - HH:mm:ss` title timestamp, started/ended time, and optional stored audio path
- `azoom_voice_meeting_utterances`
  - ordered transcript utterances with speaker user id/name/email, text content, and segment start/end timestamps

AZOOM voice participants still use heartbeat state plus LiveKit media state, while the workspace, channels, members, and text messages are persisted.

## AVA AI

- `ava_ai_conversations`
  - one current conversation per user account
- `ava_ai_messages`
  - persisted user and assistant messages
- `ava_ai_knowledge_items`
  - reusable company-scoped AI memory from previous Q/A

## Operations

- `notifications`
  - persisted user notifications with read state
- `audit_logs`
  - admin and operational audit events with actor/resource metadata
- `system_logs`
  - sanitized request id, actor, method/path/query, status, duration, IP/user-agent, error summary
- `app_settings`
  - admin-managed runtime settings

## External Integrations Not Wired In This Repository

- `payments`
- `subscriptions`
- dedicated `files` table outside chat message attachment metadata
