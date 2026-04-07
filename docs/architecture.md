# Stitch Architecture

## Product shape

Stitch is designed like an operational inbox rather than a personal finance app.

- Import receipts from multiple iPhone-native entry points.
- Normalize everything into one queue.
- Extract the minimum viable metadata.
- Make review fast.
- Upload in a single batch.

## iOS modules

### Auth

- `AuthView`
- `SessionStore`
- `SupabaseAuthService`

The app supports password or magic-link flows. When `BackendConfig.plist` is empty, Stitch falls back to a local demo session so the app still behaves like a working product while backend credentials are pending.

### Receipt capture and import

- `DocumentScannerView`
- `ReceiptImportCoordinator`
- `ReceiptFileStore`
- `AppGroupInboxService`

Each import source ends up as a locally persisted file plus a SwiftData receipt record. The Share Extension writes incoming files into the shared app-group manifest, and the main app ingests them on activation.

### OCR and extraction

- `ReceiptExtractionService`
- `ReceiptHeuristicParser`

The current scaffold performs OCR on device with Apple Vision and then runs lightweight heuristics for merchant, amount, and date extraction. This keeps the app responsive and gives you a functional end-to-end MVP without backend dependencies. The Supabase `process-receipt` function is included so the extraction pipeline can move server-side later.

### Inbox and review

- `InboxView`
- `ReceiptDetailView`
- `ReceiptRowView`

Receipts move through three states:

- `Needs Review`
- `Ready`
- `Uploaded`

### Upload orchestration

- `UploadService`
- `UploadQueueView`
- `UploadBatchRecord`

Batch upload is intentionally destination-oriented. Stitch tracks queue state and retry behavior locally, while the backend adapter is responsible for the final Expensify handoff.

## Data model

### Local SwiftData

- `ReceiptRecord`
- `UploadBatchRecord`

These models are intentionally minimal but capture what the app needs for fast local review and optimistic queue state.

### Supabase schema

The SQL migration includes:

- `profiles`
- `receipts`
- `upload_batches`
- `expensify_destinations`
- `processing_jobs`
- `audit_events`

## Expensify integration strategy

Expensify’s documented receipt import path is email-based rather than a public receipt-upload API. The backend function in this repo is set up to send one email per ready receipt to the user’s Expensify-linked address while cc’ing `receipts@expensify.com`, which preserves the app’s batch-upload UX without pretending there is a public direct-import API.

Reference:

- [Expensify travel receipt integrations](https://help.expensify.com/articles/expensify-classic/connections/Travel-receipt-integrations)

## What is deliberately not in scope

- Budget tracking
- Spend analytics
- Reimbursements
- Accounting workflows
- Finance dashboards
- Team admin controls

