# Supabase Notes

This folder contains the backend scaffold for Stitch.

- `migrations/0001_initial_schema.sql`: base schema and RLS policies
- `functions/process-receipt`: server-side receipt parsing scaffold
- `functions/batch-upload-expensify`: batch handoff adapter for Expensify email ingestion

## Environment variables

For the batch upload function:

- `RESEND_API_KEY`
- `STITCH_FROM_EMAIL`

For later richer OCR:

- `OPENAI_API_KEY`

## Why the upload function is email-based

Expensify’s current help documentation says receipt imports use email integrations and are not exposed as API-based receipt integrations:

- [Travel receipt integrations](https://help.expensify.com/articles/expensify-classic/connections/Travel-receipt-integrations)

