alter table azoom_channels
	add column if not exists access_mode varchar(24);

update azoom_channels
set access_mode = 'ALL'
where access_mode is null or trim(access_mode) = '';

alter table azoom_channels
	alter column access_mode set default 'ALL';

alter table azoom_channels
	alter column access_mode set not null;

alter table azoom_channels
	add column if not exists allowed_departments text;
