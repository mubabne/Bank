# Mailance — Latest Update

Updated: September 1, 2026

## What changed

This update changed Mailance from a mostly demo-style dashboard into a Supabase-backed application where each signed-in user has their own saved transactions.

The main improvements are:

- Transactions load from Supabase instead of re-reading Gmail every time the dashboard opens.
- Gmail sync saves imported transactions to the currently signed-in user.
- Repeated Gmail syncs update existing transactions instead of creating duplicates.
- Money is displayed in Mongolian tugriks using the `₮` symbol.
- Users can create accounts, sign in, reset passwords, and sign out.
- Every transaction can be opened to see its detailed information.
- Dashboard totals are calculated from real saved transactions instead of placeholder demo values.

## How the application works now

### 1. Authentication

The application uses Supabase Auth.

A user can:

- Create an account with their name, email, and password.
- Confirm their email if email confirmation is enabled in Supabase.
- Sign in with email and password.
- Request a password-reset email.
- Sign out from both Supabase and the connected Gmail account.

The app listens for authentication changes and automatically shows either the login page or dashboard.

### 2. Dashboard loading

Opening the dashboard no longer automatically scans Gmail.

The dashboard requests the following information from Supabase in parallel:

- The 50 most recent transactions.
- Current balance and daily/monthly totals.
- Monthly spending totals grouped by category.

This is significantly faster than downloading and parsing Gmail messages whenever the page opens.

### 3. Gmail syncing

Press **Sync inbox** on the dashboard to connect Gmail and import bank messages.

During the first sync, the app searches up to 90 days of bank-related emails. Later syncs use the previous sync time with a one-day overlap, so fewer messages need to be downloaded.

Gmail messages are downloaded in small concurrent batches instead of one at a time. The parser then attempts to identify:

- Transaction amount.
- MNT, USD, or EUR currency.
- Income or expense direction.
- Current/available balance.
- Transaction category.
- Email subject, sender, preview, and date.

Balance values are treated separately from transaction amounts to reduce incorrect parsing.

### 4. Transaction storage

Imported transactions are saved in the Supabase `transactions` table.

Each saved transaction includes:

- Owning user ID.
- Gmail message ID.
- Account ID.
- Merchant or email subject.
- Description.
- Signed amount.
- Currency.
- Category.
- Transaction date and time.
- Source.
- Email subject, sender, and preview.

The combination of user ID and Gmail message ID is unique. This makes Gmail sync safe to repeat without duplicating the same transaction.

### 5. User data isolation

Row Level Security is enabled in Supabase.

The ownership rules require transaction, account, profile, and sync-state rows to belong to the current `auth.uid()`. One signed-in user cannot read or change another user's rows through the application API.

The application only uses the Supabase publishable key. No service-role or secret key is included in the Flutter client.

### 6. Tugrik formatting

MNT is now the default currency for accounts and transactions.

Examples:

- `₮125,000`
- `-₮48,500`
- `+₮2,850,000`

An amount explicitly detected as USD or EUR will still use its correct currency symbol.

### 7. Transaction details

Tap a transaction row to open its detail sheet.

The detail sheet can display:

- Full amount.
- Merchant or subject.
- Category.
- Date and time.
- Currency.
- Import source.
- Description.
- Email sender.
- Email preview.
- Gmail import reference.

## Supabase database updates

The following migrations were deployed to the connected `BankApp` Supabase project:

1. `production_transaction_foundation`
2. `index_transaction_account_owner_fk`

They added or updated:

- MNT column defaults.
- Richer email metadata fields.
- A unique per-user Gmail account constraint.
- Transaction query indexes.
- Automatic profile creation for new Supabase users.
- Secure dashboard summary functions.
- Monthly category aggregation.
- Required authenticated-role table permissions.

The Supabase security advisor reported no security issues after these changes. The remaining performance notices only report unused indexes because the database currently has little or no transaction data.

## Important source files

- `lib/main.dart` — Supabase initialization and authentication gate.
- `lib/login_page.dart` — signup, sign-in, password reset, and login interface.
- `lib/dashboard_page.dart` — real dashboard state, Gmail sync, totals, lists, and details.
- `lib/gmail_service.dart` — Gmail authentication, message downloading, and parsing.
- `lib/bank_transaction.dart` — transaction model and currency formatting.
- `lib/transaction_repository.dart` — Supabase reads, transaction upserts, and sync state.
- `test/widget_test.dart` — login/signup UI and tugrik-formatting tests.

## Running the application

From the project directory, check the available devices:

```powershell
flutter devices
```

For Gmail syncing, use an Android device or emulator:

```powershell
flutter run -d <device-id>
```

If the correct device is already selected, this is enough:

```powershell
flutter run
```

After the app starts:

1. Create an account.
2. Confirm the email if Supabase requests confirmation.
3. Sign in.
4. Press **Sync inbox**.
5. Authorize read-only Gmail access.
6. Tap a transaction to view its details.

## Configuration

The connected Supabase URL and publishable key work as defaults. They can be overridden when running or building the app:

```powershell
flutter run --dart-define=SUPABASE_URL=https://your-project.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_your_key
```

The Google OAuth client ID can also be overridden:

```powershell
flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=your-google-client-id.apps.googleusercontent.com
```

## Verification completed

The following checks passed after the update:

```text
flutter analyze: No issues found
flutter test: 3 tests passed
Supabase security advisor: No security issues
```

The local Flutter web release command stalled without producing compiler output, so no web release bundle was certified during this update. The stalled compiler processes were stopped. Android should be used for the current Gmail authentication flow.

## Remaining production work

Before publishing the application publicly:

- Configure the final Supabase Auth site URL and allowed redirect URLs.
- Configure Google OAuth for the final Android package name and signing certificate.
- Add a custom SMTP provider for reliable production authentication emails.
- Test with real notification emails from every Mongolian bank you want to support.
- Add bank-specific parser fixtures and automated tests, since banks use different email formats.
- Add monitoring/crash reporting and a privacy policy before distributing the app.
- Produce and manually test signed Android release builds.

The application is now structured for real user-owned data, but bank-email parsing should still be tested against actual messages before treating every imported value as financially authoritative.
