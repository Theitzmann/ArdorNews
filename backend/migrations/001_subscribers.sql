-- Tracks subscription status per authenticated user.
-- Updated by a webhook handler when RevenueCat reports purchase/renewal/cancellation events.
create table if not exists subscribers (
  id uuid references auth.users(id) on delete cascade primary key,
  email text,
  revenuecat_id text unique,
  status text not null default 'inactive', -- 'active' | 'inactive' | 'expired' | 'cancelled'
  expires_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table subscribers enable row level security;

-- A user can read their own subscription row
create policy "users read own subscription"
  on subscribers for select
  using (auth.uid() = id);

-- Inserts/updates only happen via the backend's service_role key (webhook
-- handler), which bypasses RLS entirely — no insert/update policy needed
-- for regular users.
