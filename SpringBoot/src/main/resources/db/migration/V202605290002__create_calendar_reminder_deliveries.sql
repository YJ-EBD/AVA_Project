create table if not exists calendar_reminder_deliveries (
	id uuid primary key,
	event_id uuid not null references calendar_events(id) on delete cascade,
	reminder_id uuid references calendar_event_reminders(id) on delete set null,
	occurrence_start_at timestamptz not null,
	target_user_id uuid not null,
	remind_before_minutes integer not null,
	reminder_type varchar(30) not null,
	delivered_at timestamptz not null
);

create unique index if not exists uq_calendar_reminder_delivery
	on calendar_reminder_deliveries (
		event_id,
		occurrence_start_at,
		target_user_id,
		remind_before_minutes,
		reminder_type
	);

create index if not exists idx_calendar_reminder_deliveries_target
	on calendar_reminder_deliveries (target_user_id, delivered_at desc);
