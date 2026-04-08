import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

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

const ALLOWED_ORIGINS = (Deno.env.get("ALLOWED_ORIGINS") ?? "").split(",").filter(Boolean);
const MAX_RECEIPTS_PER_BATCH = 50;
const MAX_FILE_SIZE_BYTES = 20 * 1024 * 1024;

function corsHeaders(requestOrigin: string | null): HeadersInit {
  const origin = ALLOWED_ORIGINS.length === 0 || (requestOrigin && ALLOWED_ORIGINS.includes(requestOrigin))
    ? requestOrigin ?? "*"
    : ALLOWED_ORIGINS[0];
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}

async function verifyJWT(authHeader: string | null): Promise<{ userId: string; email: string } | null> {
  if (!authHeader?.startsWith("Bearer ")) return null;

  const token = authHeader.slice(7);
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !supabaseServiceKey) return null;

  const client = createClient(supabaseUrl, supabaseServiceKey);
  const { data, error } = await client.auth.getUser(token);

  if (error || !data.user) return null;
  return { userId: data.user.id, email: data.user.email ?? "" };
}

serve(async (request) => {
  const origin = request.headers.get("origin");
  const headers = corsHeaders(origin);

  if (request.method === "OPTIONS") {
    return new Response("ok", { headers });
  }

  if (request.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { headers, status: 405 });
  }

  const user = await verifyJWT(request.headers.get("Authorization"));
  if (!user) {
    return Response.json({ error: "Unauthorized" }, { headers, status: 401 });
  }

  let body: BatchUploadRequest;
  try {
    body = (await request.json()) as BatchUploadRequest;
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { headers, status: 400 });
  }

  if (!body.expensifyEmail || typeof body.expensifyEmail !== "string") {
    return Response.json({ error: "expensifyEmail is required" }, { headers, status: 400 });
  }

  const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
  if (!emailRegex.test(body.expensifyEmail)) {
    return Response.json({ error: "expensifyEmail is not a valid email address" }, { headers, status: 400 });
  }

  if (!Array.isArray(body.receipts) || body.receipts.length === 0) {
    return Response.json({ error: "receipts array is required and must not be empty" }, { headers, status: 400 });
  }

  if (body.receipts.length > MAX_RECEIPTS_PER_BATCH) {
    return Response.json(
      { error: `Batch size exceeds maximum of ${MAX_RECEIPTS_PER_BATCH} receipts` },
      { headers, status: 400 }
    );
  }

  for (const receipt of body.receipts) {
    const estimatedBytes = Math.ceil((receipt.base64Data?.length ?? 0) * 0.75);
    if (estimatedBytes > MAX_FILE_SIZE_BYTES) {
      return Response.json(
        { error: `Receipt '${receipt.fileName}' exceeds the 20 MB size limit` },
        { headers, status: 413 }
      );
    }
  }

  const resendApiKey = Deno.env.get("RESEND_API_KEY");
  const stitchFromEmail = Deno.env.get("STITCH_FROM_EMAIL");

  if (!resendApiKey || !stitchFromEmail) {
    const simulated = body.receipts.map((receipt) => ({
      receiptId: receipt.receiptId,
      status: receipt.amount > 0 ? "uploaded" : "failed",
      message: receipt.amount > 0
        ? "Simulated upload. Configure RESEND_API_KEY and STITCH_FROM_EMAIL as Edge Function secrets for live delivery."
        : "Amount must be greater than zero.",
    }));

    return Response.json({ batchId: crypto.randomUUID(), results: simulated }, { headers, status: 200 });
  }

  const results = await Promise.all(
    body.receipts.map(async (receipt) => {
      if (receipt.amount <= 0) {
        return {
          receiptId: receipt.receiptId,
          status: "failed",
          message: "Amount must be greater than zero.",
        };
      }

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
            text: buildBody(receipt, user.email),
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
    })
  );

  return Response.json({ batchId: crypto.randomUUID(), results }, { headers, status: 200 });
});

function buildSubject(receipt: UploadReceipt): string {
  const formatter = new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: receipt.currencyCode || "USD",
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
  const amount = Number.isFinite(receipt.amount) ? formatter.format(receipt.amount) : "Receipt";
  const merchant = receipt.merchant || "Receipt";
  return `${merchant} ${amount}`;
}

function buildBody(receipt: UploadReceipt, uploaderEmail: string): string {
  const formatter = new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: receipt.currencyCode || "USD",
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
  const formattedAmount = Number.isFinite(receipt.amount) ? formatter.format(receipt.amount) : "Unknown";

  return [
    "Receipt uploaded by Stitch.",
    "",
    `Merchant: ${receipt.merchant || "Unknown"}`,
    `Amount: ${formattedAmount}`,
    `Currency: ${receipt.currencyCode || "USD"}`,
    `Date: ${receipt.purchaseDate ?? "Unknown"}`,
    `Uploaded by: ${uploaderEmail}`,
    "",
    "This email is intended for Expensify receipt ingestion.",
  ].join("\n");
}
