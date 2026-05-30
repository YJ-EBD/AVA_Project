alter table calendar_events
	add column if not exists team_id varchar(80);

alter table calendar_events
	add column if not exists importance varchar(20) not null default 'NORMAL';

create index if not exists idx_calendar_events_team
	on calendar_events (team_id, start_at)
	where deleted_at is null;
