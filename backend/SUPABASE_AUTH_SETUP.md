# Supabase Auth & Subscriber Setup (Phase A)

This guide prepares Supabase to handle **user login** and **subscription
tracking** for ARDOR News. It is written for a non-expert — follow the steps
in order. Everything here is done in the Supabase Dashboard (your browser);
no code changes to the Flutter app happen in this phase.

> **What we're building:** users will log in *without a password* (they get a
> "magic link" by email), and we'll keep one row per user in a `subscribers`
> table recording whether their subscription is active. A future webhook from
> RevenueCat will keep that row up to date.

---

## A quick word on the two Supabase keys (read this first)

Supabase gives your project **two different keys**, and it's critical not to
mix them up:

| Key | Env var name in this project | Where it's allowed | What it can do |
|-----|------------------------------|--------------------|----------------|
| **service_role** (secret) | `SUPABASE_KEY` | **Backend only** (Railway) | Full admin. Ignores all security rules (RLS). |
| **anon** (public) | `SUPABASE_ANON_KEY` | **Flutter app** + backend | Limited. Always restricted by security rules (RLS). |

- The backend already uses the **service_role** key — confusingly, in our code
  the env var for it is named `SUPABASE_KEY` (see `storage.py`). That key holds
  the service_role secret. **Leave it as-is.** The new webhook that writes to
  `subscribers` will use this same key.
- The Flutter app will later need the **anon** key (`SUPABASE_ANON_KEY`). We're
  only *recording* it in this phase — see Step 4. The app will **never** receive
  the service_role key.

⚠️ **The service_role key must never appear in the Flutter app or in any
public/client code.** Anyone holding it can read and modify every user's data.

---

## Step 1 — Enable the Email auth provider

1. Open your project at <https://supabase.com/dashboard>.
2. In the left sidebar, click **Authentication**.
3. Click **Providers** (under the "Configuration" area).
4. Find **Email** in the list and click it to expand it.
5. Make sure the **Enable Email provider** toggle is **ON**.
6. Click **Save**.

---

## Step 2 — Use magic link / OTP (passwordless), not passwords

We do **not** want users creating passwords. Still inside the **Email**
provider settings from Step 1:

1. Turn **OFF** **"Confirm password"** / any "Enable password sign-in" style
   option, if present. We are not using passwords at all.
2. Make sure email-based sign-in is allowed (this is what powers the magic
   link and the 6-digit OTP code). In current Supabase this is on by default
   once the Email provider is enabled.
3. Click **Save**.

Then check the email templates so the login email makes sense:

4. Go to **Authentication → Emails** (sometimes labelled **Email Templates**).
5. Look at the **Magic Link** template — this is the email users receive to log
   in. You can leave the default wording for now; just confirm it exists.

> **Magic link vs. OTP — same thing, two formats.** A magic link is a button/URL
> the user taps in their email; an OTP is a short numeric code they type into the
> app. Both are passwordless and both work with the setup above. The Flutter app
> (next phase) will choose which one to present.

> **Heads-up for later:** when the app starts sending magic links, you'll add the
> app's redirect URL under **Authentication → URL Configuration**. Not needed in
> Phase A.

---

## Step 3 — Create the `subscribers` table

This creates the table that stores each user's subscription status, with
security rules so users can only read **their own** row.

1. In the left sidebar, click **SQL Editor**.
2. Click **+ New query**.
3. Open the file `backend/migrations/001_subscribers.sql` from this repo, copy
   its **entire** contents, and paste it into the editor.
4. Click **Run** (or press Ctrl/Cmd + Enter).
5. You should see a success message. To verify, go to **Table Editor** in the
   sidebar — a `subscribers` table should now be listed.

What that SQL does, in plain terms:
- Creates a `subscribers` table keyed to Supabase's built-in `auth.users`. If a
  user is deleted, their subscriber row is automatically removed.
- Turns on **Row Level Security (RLS)** so the table is locked down by default.
- Adds **one rule**: a logged-in user may *read* only the row that belongs to
  them (`auth.uid() = id`).
- Adds **no** insert/update rules on purpose. Writes only ever come from the
  backend using the **service_role** key, which bypasses RLS — so regular users
  can never create or edit subscription rows themselves.

---

## Step 4 — Find and record the anon key (for the Flutter app, later)

The Flutter app will need the **anon** key to log users in and read their
subscription. Locate it now and store it safely:

1. In the left sidebar, click **Project Settings** (the gear icon).
2. Click **API** (or **API Keys**).
3. You'll see two values relevant to us:
   - **Project URL** → this is `SUPABASE_URL` (already in use).
   - **anon / public** key → this is the new **`SUPABASE_ANON_KEY`**.
4. Copy the **anon / public** key.
5. Paste it into your backend `.env` file as:
   ```
   SUPABASE_ANON_KEY=<the anon key you copied>
   ```
   (See `backend/.env.example` for the full list of expected variables.)

**Why the app needs the anon key and never the service_role key:**
- The **anon key is public by design** — it's safe to ship inside the Android
  app. On its own it can't bypass anything; every request it makes is filtered
  by the RLS rule from Step 3, so a user can only ever see their own data.
- The **service_role key is a master key**. If it were embedded in the app, an
  attacker could extract it from the APK and read or alter every user's
  subscription. That's why it stays exclusively on the backend (Railway).

> On the same **API Keys** page you'll also see the **service_role** key clearly
> marked as secret. Do **not** put that one in the app — it stays in the
> backend's `SUPABASE_KEY` variable only.

---

## Done — what's ready after this phase

- ✅ Passwordless (magic-link / OTP) email login is enabled in Supabase.
- ✅ The `subscribers` table exists with RLS protecting each user's row.
- ✅ The `SUPABASE_ANON_KEY` is recorded for the app to use later.

**Next phases (not done here):** wiring Supabase login into the Flutter app,
and building the RevenueCat webhook handler that writes subscription status
into the `subscribers` table using the service_role key.
