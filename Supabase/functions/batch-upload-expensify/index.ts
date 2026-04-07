import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

type UploadReceipt = {
  receiptId: string;
  fileName: string;
  contentType: string;
  merchant: string;
  amount: number;
  currencyCode: string;
  purchaseDate?: string | null;
  base64Data: string;
};

type BatchUploadRequest = {
  expensifyEmail: string;
  receipts: UploadReceipt[];
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = (await request.json()) as BatchUploadRequest;
    const resendApiKey = Deno.env.get("RESEND_API_KEY");
    const stitchFromEmail = Deno.env.get("STITCH_FROM_EMAIL");

    if (!body.expensifyEmail) {
      return Response.json({ error: "expensifyEmail is required" }, { headers: corsHeaders, status: 400 });
    }

    if (!resendApiKey || !stitchFromEmail) {
      const simulated = body.receipts.map((receipt) => ({
        receiptId: receipt.receiptId,
        status: receipt.amount > 0 ? "uploaded" : "failed",
        message: receipt.amount > 0
          ? "Simulated upload. Configure RESEND_API_KEY and STITCH_FROM_EMAIL for live delivery."
          : "Amount must be greater than zero.",
      }));

      return Response.json({
        batchId: crypto.randomUUID(),
        results: simulated,
      }, {
        headers: corsHeaders,
        status: 200,
      });
    }

    const results = await Promise.all(body.receipts.map(async (receipt) => {
      try {
        const response = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: {
            Authorization: `Bearer ${resendApiKey}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            from: stitchFromEmail,
            to: [body.expensifyEmail],
            cc: ["receipts@expensify.com"],
            subject: buildSubject(receipt),
            text: buildBody(receipt),
            attachments: [
              {
                filename: receipt.fileName,
                content: receipt.base64Data,
              },
            ],
          }),
        });

        if (!response.ok) {
          const payload = await response.text();
          throw new Error(payload || "Mail delivery failed");
        }

        return {
          receiptId: receipt.receiptId,
          status: "uploaded",
          message: "Receipt emailed to Expensify.",
        };
      } catch (error) {
        return {
          receiptId: receipt.receiptId,
          status: "failed",
          message: error instanceof Error ? error.message : "Unknown upload error",
        };
      }
    }));

    return Response.json({
      batchId: crypto.randomUUID(),
      results,
    }, {
      headers: corsHeaders,
      status: 200,
    });
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Unknown error" },
      { headers: corsHeaders, status: 500 },
    );
  }
});

function buildSubject(receipt: UploadReceipt) {
  const amount = Number.isFinite(receipt.amount) ? `${receipt.currencyCode} ${receipt.amount.toFixed(2)}` : "Receipt";
  const merchant = receipt.merchant || "Receipt";
  return `${merchant} ${amount}`;
}

function buildBody(receipt: UploadReceipt) {
  return [
    "Receipt uploaded by Stitch.",
    "",
    `Merchant: ${receipt.merchant || "Unknown"}`,
    `Amount: ${receipt.currencyCode} ${receipt.amount.toFixed(2)}`,
    `Date: ${receipt.purchaseDate ?? "Unknown"}`,
    "",
    "This email is intended for Expensify receipt ingestion.",
  ].join("\n");
}

