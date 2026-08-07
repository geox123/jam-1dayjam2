create table if not exists public.leaderboard_scores (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  player_name text not null check (char_length(player_name) between 1 and 12),
  score integer not null check (score between 0 and 1000000),
  duration_seconds numeric(8,2) not null check (duration_seconds between 0 and 3600),
  created_at timestamptz not null default now()
);

create index if not exists leaderboard_scores_score_idx
  on public.leaderboard_scores (score desc, created_at asc);

alter table public.leaderboard_scores enable row level security;

create policy "Scores are readable through the leaderboard function"
  on public.leaderboard_scores for select
  to service_role using (true);

revoke all on public.leaderboard_scores from anon, authenticated;
