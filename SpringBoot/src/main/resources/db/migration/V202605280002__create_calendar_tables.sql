create table if not exists calendar_categories (
	id uuid primary key,
	name varchar(80) not null,
	color varchar(30) not null,
	icon varchar(60),
	scope varchar(30) not null,
	owner_user_id uuid,
	is_default boolean not null default false,
	sort_order integer not null default 100,
	created_at timestamptz not null,
	updated_at timestamptz not null
);

create index if not exists idx_calendar_categories_owner
	on calendar_categories (owner_user_id, is_default, sort_order);

create unique index if not exists uq_calendar_default_category_name
	on calendar_categories (name)
	where is_default = true;

create table if not exists calendar_events (
	id uuid primary key,
	title varchar(200) not null,
	description text,
	start_at timestamptz not null,
	end_at timestamptz not null,
	all_day boolean not null default false,
	location varchar(240),
	category_id uuid,
	color varchar(30),
	status varchar(30) not null,
	meeting_status varchar(40) not null default 'RESERVED',
	visibility varchar(30) not null,
	detail_visibility varchar(30) not null,
	owner_user_id uuid not null,
	created_by uuid not null,
	updated_by uuid,
	memo text,
	project_name varchar(160),
	created_at timestamptz not null,
	updated_at timestamptz not null,
	deleted_at timestamptz
);

create index if not exists idx_calendar_events_owner_time
	on calendar_events (owner_user_id, start_at, end_at)
	where deleted_at is null;

create index if not exists idx_calendar_events_range
	on calendar_events (start_at, end_at)
	where deleted_at is null;

create index if not exists idx_calendar_events_category
	on calendar_events (category_id, start_at)
	where deleted_at is null;

create table if not exists calendar_event_attendees (
	id uuid primary key,
	event_id uuid not null references calendar_events(id) on delete cascade,
	user_id uuid,
	display_name varchar(120) not null,
	department varchar(120),
	position varchar(120),
	email varchar(160),
	response_status varchar(30) not null,
	response_message varchar(500),
	responded_at timestamptz,
	created_at timestamptz not null
);

create index if not exists idx_calendar_attendees_event
	on calendar_event_attendees (event_id, created_at);

create index if not exists idx_calendar_attendees_user
	on calendar_event_attendees (user_id);

create table if not exists calendar_event_reminders (
	id uuid primary key,
	event_id uuid not null references calendar_events(id) on delete cascade,
	remind_before_minutes integer not null,
	reminder_type varchar(30) not null,
	target_type varchar(30) not null,
	target_id varchar(120),
	is_sent boolean not null default false,
	sent_at timestamptz,
	created_at timestamptz not null
);

create index if not exists idx_calendar_reminders_event
	on calendar_event_reminders (event_id, remind_before_minutes);

create table if not exists calendar_event_recurrences (
	id uuid primary key,
	event_id uuid not null unique references calendar_events(id) on delete cascade,
	recurrence_type varchar(30) not null,
	interval_value integer not null default 1,
	days_of_week varchar(40),
	day_of_month integer,
	end_type varchar(30) not null,
	until_date date,
	occurrence_count integer,
	rrule text,
	timezone varchar(80) not null default 'Asia/Seoul',
	created_at timestamptz not null
);

create table if not exists calendar_event_files (
	id uuid primary key,
	event_id uuid not null references calendar_events(id) on delete cascade,
	file_id varchar(120),
	file_name varchar(240) not null,
	file_path varchar(800),
	file_type varchar(80),
	file_size bigint,
	source_type varchar(30) not null,
	linked_at timestamptz not null
);

create index if not exists idx_calendar_files_event
	on calendar_event_files (event_id, linked_at);

create table if not exists calendar_event_notion_links (
	id uuid primary key,
	event_id uuid not null references calendar_events(id) on delete cascade,
	notion_page_id varchar(160),
	notion_database_id varchar(160),
	notion_title varchar(240) not null,
	notion_url varchar(1000),
	linked_at timestamptz not null
);

create index if not exists idx_calendar_notion_event
	on calendar_event_notion_links (event_id, linked_at);

create table if not exists calendar_event_chat_links (
	id uuid primary key,
	event_id uuid not null references calendar_events(id) on delete cascade,
	chat_room_id varchar(120) not null,
	chat_room_name varchar(160),
	source_message_id varchar(120),
	source_message_preview varchar(1000),
	linked_at timestamptz not null
);

create index if not exists idx_calendar_chat_event
	on calendar_event_chat_links (event_id, linked_at);

create table if not exists calendar_event_azoom_links (
	id uuid primary key,
	event_id uuid not null references calendar_events(id) on delete cascade,
	azoom_meeting_id varchar(160),
	azoom_room_id varchar(160),
	azoom_join_url varchar(1000),
	azoom_recording_id varchar(160),
	azoom_transcript_id varchar(160),
	azoom_minutes_id varchar(160),
	linked_at timestamptz not null
);

create index if not exists idx_calendar_azoom_event
	on calendar_event_azoom_links (event_id, linked_at);

create table if not exists calendar_event_audit_logs (
	id uuid primary key,
	event_id uuid,
	action_type varchar(80) not null,
	actor_user_id uuid not null,
	before_json text,
	after_json text,
	source varchar(40) not null,
	created_at timestamptz not null
);

create index if not exists idx_calendar_audit_event
	on calendar_event_audit_logs (event_id, created_at desc);
