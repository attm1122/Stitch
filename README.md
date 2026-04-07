# Stitch

Stitch is a native iOS receipt inbox for Expensify. It is intentionally narrow: collect receipts from camera scans, Photos, Files, and the iOS Share Sheet, review extracted metadata, and batch upload ready receipts with minimal friction.

## What ships in this repo

- Native iOS app built with SwiftUI and SwiftData
- Share Extension for importing receipts from other apps
- On-device OCR and receipt heuristics for merchant, amount, and date extraction
- Receipt inbox with `Needs Review`, `Ready`, and `Uploaded` states
- Multi-select and batch upload flow
- Upload queue, retry handling, and sync history
- Supabase schema and Edge Function scaffolding for server-side processing and Expensify handoff

## Product scope

Stitch does not try to become a broader finance product. There is no budgeting, spend analytics, reimbursements, ledgering, or accounting dashboard surface area in this MVP. The product is focused entirely on receipt capture, collation, review, and upload.

## Architecture

- iOS app: Swift + SwiftUI
- Local state: SwiftData
- OCR: Apple Vision on device for the current MVP scaffold
- Backend scaffold: Supabase Postgres + Edge Functions
- Expensify destination: batch upload adapter designed around email ingestion

More detail lives in [docs/architecture.md](./docs/architecture.md).

## Important Expensify note

Stitch is built around Expensify’s currently documented receipt-ingestion flow. Expensify’s help center says receipt imports are handled through email integrations and explicitly notes that API-based receipt imports are not currently offered:

- [Travel receipt integrations](https://help.expensify.com/articles/expensify-classic/connections/Travel-receipt-integrations)

That means the backend adapter in this repo is set up to batch hand off receipts through a mail bridge rather than a direct public receipt-upload API. In production, the sender domain or addresses used by the backend need to be whitelisted with Expensify for a custom receipt integration.

## Running the app

1. Open [Stitch.xcodeproj](./Stitch.xcodeproj) in Xcode.
2. Update the bundle identifiers, signing team, and app group if you want to run the share extension on your own Apple account.
3. Fill in `Resources/BackendConfig.plist` if you want live Supabase auth and the Edge Function upload path.
4. Build and run the `Stitch` scheme.

The app also works in local demo mode when backend configuration is blank, which is useful for validating the UX before wiring credentials.

## Backend setup

1. Create a Supabase project.
2. Apply [Supabase/migrations/0001_initial_schema.sql](./Supabase/migrations/0001_initial_schema.sql).
3. Deploy the two Edge Functions in `Supabase/functions/`.
4. Set function secrets for `RESEND_API_KEY`, `STITCH_FROM_EMAIL`, and any OpenAI secret you want to use later for richer receipt parsing.
5. Copy the generated URLs and keys into `Resources/BackendConfig.plist`.

## Repo layout

- `App/`: app bootstrap and root flows
- `Features/`: auth, inbox, detail, upload queue, capture
- `Models/`: SwiftData models and shared value types
- `Services/`: auth, import, OCR, shared inbox, upload orchestration
- `ShareExtension/`: iOS Share Extension target
- `Supabase/`: schema and function scaffold
- `Tests/`: parser-focused smoke tests

