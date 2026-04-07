# Expensify Integration Notes

Stitch is built around Expensify’s currently documented receipt-import mechanism.

## Current documented constraints

Expensify’s help article says:

- custom receipt integrations are set up by emailing `receiptintegration@expensify.com`
- receipt emails should be sent to the user and cc `receipts@expensify.com`
- receipt imports are not currently exposed as API-based integrations

Reference:

- [Travel receipt integrations](https://help.expensify.com/articles/expensify-classic/connections/Travel-receipt-integrations)

## Practical implication for Stitch

The iOS app keeps the premium user-facing flow:

- collect receipts quickly
- review them in one inbox
- select ready items
- upload in one action

The backend fulfills that action by sending a batch of individual receipt emails through a trusted mail provider. That preserves the UX benefit without relying on an undocumented upload API.

## Production checklist

- Register the sender address or domain with Expensify’s custom receipt integration process.
- Verify the same sender in your outbound mail provider.
- Store each uploaded receipt and batch audit trail in Supabase.
- Alert or retry when a message send fails.

