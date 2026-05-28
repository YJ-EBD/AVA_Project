alter table azoom_channels
	add column if not exists access_mode varchar(24) not null default 'ALL';

alter table azoom_channels
	add column if not exists allowed_departments text;
