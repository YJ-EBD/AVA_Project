update user_accounts
set display_name = '박주한',
    role = 'ADMIN',
    enabled = true,
    updated_at = now()
where lower(email) = 'admin@ava.admin';

update user_profiles
set nickname = '박주한',
    company_name = coalesce(nullif(company_name, ''), 'ABBA-S'),
    department = coalesce(nullif(department, ''), 'Management'),
    position = coalesce(nullif(position, ''), 'Admin')
where account_id in (
    select id from user_accounts where lower(email) = 'admin@ava.admin'
);

update user_accounts
set role = 'SUPERUSER',
    enabled = true,
    updated_at = now()
where lower(email) = 'amos5105@naver.com';
