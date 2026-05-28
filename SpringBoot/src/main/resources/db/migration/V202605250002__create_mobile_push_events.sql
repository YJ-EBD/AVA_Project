create table if not exists mobile_push_events (
	id uuid primary key,
	account_id uuid not null references user_accounts(id) on delete cascade,
	type varchar(60) not null,
	title varchar(160) not null,
	body varchar(1000) not null,
	room_id varchar(120),
	room_title varchar(160),
	sender_name varchar(160),
	sender_nickname varchar(160),
	avatar_color varchar(32),
	source_type varchar(80),
	source_id varchar(160),
	data_json text,
	created_at timestamp with time zone not null
);

create index if not exists idx_mobile_push_events_account_created
on mobile_push_events (account_id, created_at desc);
