-- 홈구장 계정 동기화용 Supabase 스키마
-- Supabase 대시보드 → SQL Editor 에 통째로 붙여 넣어 한 번 실행한다. 다시 실행해도 안전하다.
-- 설명과 설정 순서는 docs/sync-setup.md 를 본다.

-- 계정(auth.users)마다 한 줄. 카드·포인트·라인업·응원팀·직관 기록·응원가 지정을 JSON 한 덩어리로 담는다.
create table if not exists public.user_state (
    user_id uuid primary key references auth.users (id) on delete cascade,
    -- 저장할 때마다 1씩 올라간다. 다른 기기가 먼저 저장했는지 알아내는 데 쓴다.
    revision bigint not null default 1,
    data jsonb not null,
    updated_at timestamptz not null default now()
);

alter table public.user_state enable row level security;

-- 본인 줄만 읽고 쓸 수 있다. 앱에 들어 있는 anon 키로는 다른 사람 데이터를 볼 수 없다.
drop policy if exists "own row select" on public.user_state;
create policy "own row select" on public.user_state
    for select to authenticated using (user_id = auth.uid());

drop policy if exists "own row insert" on public.user_state;
create policy "own row insert" on public.user_state
    for insert to authenticated with check (user_id = auth.uid());

drop policy if exists "own row update" on public.user_state;
create policy "own row update" on public.user_state
    for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "own row delete" on public.user_state;
create policy "own row delete" on public.user_state
    for delete to authenticated using (user_id = auth.uid());

-- 저장할 때 시각을 서버가 찍는다 (기기 시계가 틀려도 순서가 어긋나지 않게)
create or replace function public.touch_user_state() returns trigger
language plpgsql as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

drop trigger if exists touch_user_state on public.user_state;
create trigger touch_user_state before insert or update on public.user_state
    for each row execute function public.touch_user_state();

-- 앱 안에서 계정 삭제 (App Store 규정: 계정을 만들 수 있으면 앱 안에서 지울 수도 있어야 한다)
-- auth.users 줄이 지워지면 user_state 도 같이 지워진다.
create or replace function public.delete_my_account() returns void
language sql security definer set search_path = '' as $$
    delete from auth.users where id = auth.uid();
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
