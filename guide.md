# Mailance setup guide

Mailance is a Flutter app that reads bank-notification emails from Gmail with
read-only permission, extracts transactions, and shows them on the dashboard.

## What is already configured

- Google Cloud project: `bankappmobileflutter`
- Gmail API: enabled
- OAuth consent scope: `gmail.readonly`
- Android debug package: `com.example.bank_app`
- Android debug SHA-1: `75:5C:34:16:D8:F5:71:80:DB:62:2D:81:CF:D4:0C:CB:B7:AF:8C:E5`
- Android OAuth client: `1034954657947-ocmugk4pe4020msh4iq4g8apsb7up4ak.apps.googleusercontent.com`
- OAuth server/web client used by the app: `1034954657947-rto256igsjd879sd027vac1438u6m211.apps.googleusercontent.com`
- Google Auth branding name: Mailance

OAuth client IDs are public configuration. Never put a Google OAuth client
secret, Supabase secret key, or Supabase `service_role` key in this Flutter app.

## Run it on an Android phone

1. In Google Cloud Console, open **Google Auth Platform > Audience**.
2. While the app is in Testing, add every Gmail address that will test the app
   under **Test users**. Otherwise Google can show an `access_denied` or
   "app has not completed verification" error.
3. On the Android phone, enable Developer options and USB debugging, then connect
   it to the computer.
4. From this project directory, run:

   ```powershell
   flutter devices
   flutter run -d YOUR_DEVICE_ID
   ```

5. Tap **Continue with Google**, choose a test-user Gmail account, and approve
   the read-only Gmail permission.
6. The connected Gmail address appears on the dashboard. Tap **Sync Gmail** to
   scan for transaction messages.

If Gradle reports `Unable to establish loopback connection`, Java is being
blocked from opening a local Windows socket. Run the command from a normal
Android Studio or PowerShell terminal, close stale Java/Gradle processes, and
check whether a VPN, firewall, or endpoint-security rule is blocking local Java
connections. Then run `flutter clean`, `flutter pub get`, and try again.

The app requests only `https://www.googleapis.com/auth/gmail.readonly`. It
cannot send, edit, or delete email. The current scanner checks at most 75 messages
from the last 90 days. Its query and parser are in `lib/gmail_service.dart`.
Bank email formats differ, so edit the Gmail search query, amount expressions,
and category rules there when testing against your bank's actual messages.

### Google branding logo

The app logo is `assets/mailance_logo.png`. To show it on Google's consent
screen, manually open **Google Auth Platform > Branding > App logo**, upload
that file, and save. This is optional for local testing.

### Release builds

The configured Android OAuth client matches the current debug signing key only.
Before publishing:

1. Get the SHA-1 of the release keystore, or the **Play App Signing** SHA-1 from
   Google Play Console.
2. Create another Android OAuth client in the same Google Cloud project.
3. Use package name `com.example.bank_app` and the release SHA-1.
4. Move the OAuth app from Testing to Production when ready. Because Gmail
   readonly is a sensitive scope, Google may require app verification, a privacy
   policy, and an explanation of how Gmail data is used.

The current Google client setup is for Android. An iPhone release needs a
separate iOS OAuth client for bundle ID `com.example.bankApp` plus the iOS URL
scheme configuration required by `google_sign_in`.

## Do I need Supabase?

No database is required for the current demo. The app can read Gmail and display
the parsed results in memory. Data disappears when the app is restarted.

Use Supabase when you want transaction history to persist, sync across devices,
support multiple users, allow corrections/categories, or keep sync status.

Important: the current direct Google/Gmail sign-in does **not** automatically
create a Supabase Auth user. Before the Flutter app writes to the tables below,
add Supabase Auth and sign the user into Supabase. The database policies use
`auth.uid()` to keep each user's financial data private. Do not turn RLS off and
do not use the service-role key as a shortcut.

## Create the Supabase database

1. Create a project at Supabase.
2. Open **SQL Editor > New query**.
3. Paste and run the SQL below.

```sql
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  bank_name text,
  currency text not null default 'USD' check (char_length(currency) = 3),
  current_balance numeric(18, 2),
  last_synced_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (id, user_id)
);

create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  account_id uuid,
  gmail_message_id text not null,
  merchant_name text,
  description text,
  amount numeric(18, 2) not null,
  currency text not null default 'USD' check (char_length(currency) = 3),
  category text not null default 'Bank activity',
  transacted_at timestamptz not null,
  source text not null default 'gmail' check (source in ('gmail', 'manual')),
  email_subject text,
  created_at timestamptz not null default now(),
  unique (user_id, gmail_message_id),
  foreign key (account_id, user_id)
    references public.accounts (id, user_id)
);

create table public.sync_state (
  user_id uuid primary key references auth.users (id) on delete cascade,
  gmail_email text,
  gmail_history_id text,
  search_query text,
  last_sync_at timestamptz,
  sync_status text not null default 'idle'
    check (sync_status in ('idle', 'running', 'success', 'error')),
  last_error text,
  messages_scanned integer not null default 0 check (messages_scanned >= 0),
  updated_at timestamptz not null default now()
);

create index accounts_user_id_idx
  on public.accounts (user_id);

create index transactions_user_date_idx
  on public.transactions (user_id, transacted_at desc);

create index transactions_account_id_idx
  on public.transactions (account_id)
  where account_id is not null;

alter table public.profiles enable row level security;
alter table public.accounts enable row level security;
alter table public.transactions enable row level security;
alter table public.sync_state enable row level security;

create policy "users manage their profile"
on public.profiles
for all
to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

create policy "users manage their accounts"
on public.accounts
for all
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "users manage their transactions"
on public.transactions
for all
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "users manage their sync state"
on public.sync_state
for all
to authenticated
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

revoke all on public.profiles from anon;
revoke all on public.accounts from anon;
revoke all on public.transactions from anon;
revoke all on public.sync_state from anon;

grant select, insert, update, delete on public.profiles to authenticated;
grant select, insert, update, delete on public.accounts to authenticated;
grant select, insert, update, delete on public.transactions to authenticated;
grant select, insert, update, delete on public.sync_state to authenticated;
```

### Data rules

- Save income as a positive amount and spending as a negative amount.
- Use three-letter uppercase currency codes such as `USD` or `MNT`.
- `gmail_message_id` plus `user_id` prevents the same email being imported twice.
- `numeric(18,2)` is used for money; do not use floating-point database columns.
- Save timestamps as `timestamptz` and display them in the phone's local timezone.
- Do not store the raw Gmail message body unless it is genuinely required.
- Do not store Google access or refresh tokens in these public tables.

## Connect Flutter to the new Supabase project

After creating the project, copy only these two values from **Project Settings >
API**:

- Project URL
- Publishable key (often starts with `sb_publishable_`)

Then add the Flutter package:

```powershell
flutter pub add supabase_flutter
```

Initialize it before `runApp`:

```dart
await Supabase.initialize(
  url: const String.fromEnvironment('SUPABASE_URL'),
  anonKey: const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
);
```

Run with:

```powershell
flutter run -d YOUR_DEVICE_ID `
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
```

Do not commit real environment values. A publishable key is designed for client
apps, but RLS still must protect every table.

For the cleanest final architecture, use Supabase Auth as the app login, request
the Gmail readonly scope during Google authorization, and store parsed rows with
the Supabase user's `auth.uid()`. If you later want Gmail syncing while the app is
closed, move the Gmail API call to a protected backend or Supabase Edge Function;
refresh tokens and service-role credentials must stay server-side.

## Suggested build order from here

1. Confirm the current Gmail login and sync on an Android test phone.
2. Adjust the parser for the exact bank email template.
3. Create Supabase and run the SQL above.
4. Add Supabase Auth, then wire transaction upserts and sync state.
5. Test two different accounts to confirm RLS keeps their data separate.
6. Add the release signing SHA-1 and complete Google verification before launch.
