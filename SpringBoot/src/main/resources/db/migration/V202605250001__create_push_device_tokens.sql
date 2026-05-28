create table if not exists push_device_tokens (
    id uuid primary key,
    account_id uuid not null references user_accounts(id) on delete cascade,
    token varchar(2048) not null unique,
    platform varchar(40) not null,
    app_version varchar(40) not null,
    device_id varchar(160) not null,
    enabled boolean not null default true,
    created_at timestamp with time zone not null,
    updated_at timestamp with time zone not null,
    last_seen_at timestamp with time zone not null
);

create index if not exists idx_push_device_tokens_account_enabled
on push_device_tokens (account_id, enabled);

create index if not exists idx_push_device_tokens_last_seen
on push_device_tokens (last_seen_at desc);
