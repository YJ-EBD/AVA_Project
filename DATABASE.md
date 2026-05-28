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
- `chat_mention_notifications`
  - per-user mention inbox with checked/read state, room/message pointers, mention display label, and newest-first indexes for fast notification-center loading
- `chat_talk_drawer_items`
  - media/file drawer items
- MongoDB `chat_messages`
  - optional message document mirror/history path

## AZOOM

- `azooms`
  - company-scoped AZOOM workspace record
- `azoom_channels`
  - persisted voice channels, sort order, archive state
- `azoom_members`
  - workspace members and AZOOM roles: `OWNER`, `MANAGER`, `MEMBER`
- `azoom_voice_meeting_transcripts`
  - Notiva AI voice-channel transcript headers, company/workspace, voice channel, room name, `REALTIME` or `BATCH_AUDIO`, `yyyy:MM:dd (E) - HH:mm:ss` title timestamp, started/ended time, and optional stored audio path
- `azoom_voice_meeting_utterances`
  - ordered transcript utterances with speaker user id/name/email, text content, and segment start/end timestamps

AZOOM voice participants still use heartbeat state plus LiveKit media state, while the workspace, voice channels, members, and meeting transcripts are persisted.

## AVA_stock

AVA_stock is implemented inside the existing Spring Boot schema with Hibernate `ddl-auto=update`.

- `ava_stock_product_models`
  - product model master such as ALLION or later models
- `ava_stock_bom_versions`
  - fixed BOM snapshot versions per product model
- `ava_stock_bom_items`
  - BOM checklist rows and required part quantities
- `ava_stock_parts`
  - part master
- `ava_stock_part_qr_codes`
  - QR values for part boxes
- `ava_stock_part_stock_movements`
  - movement ledger for `PURCHASE_IN`, `PRODUCTION_USE`, `AS_USE`, `ADJUSTMENT_IN`, `ADJUSTMENT_OUT`, and `REVERSAL`
- `ava_stock_product_receipts`
  - semi-finished product receipt batches
- `ava_stock_product_units`
  - one physical product unit per QR, with fixed `bom_version_id`
- `ava_stock_product_status_history`
  - product lifecycle changes
- `ava_stock_product_operations`
  - manufacturing and A/S operations
- `ava_stock_operation_check_items`
  - operation-specific checklist state: `PENDING`, `USED`, `NOT_USED`
- `ava_stock_service_cases`
  - A/S case headers
- `ava_stock_finished_products`
  - manufactured finished-product records
- `ava_stock_destinations`
  - shipment destinations
- `ava_stock_shipments`
  - shipment headers
- `ava_stock_shipment_items`
  - products included in each shipment

Part stock is calculated from the sum of `ava_stock_part_stock_movements.quantity_delta`, not from a mutable stock counter. Manufacturing and A/S check histories are separate operation rows and never overwrite each other.

AVA_stock also exposes Spring MVC web pages:

- `/stock`
  - inventory, shipment, part inventory, and model stock dashboard backed by the dashboard APIs
- `/stock/admin`
  - ADMIN/SUPERUSER master UI for product models, BOM versions, BOM items, part masters, and part QR codes

The MVC pages are served by Spring Boot and authenticate API calls through the existing JWT login flow; they do not create a separate web auth schema.

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
