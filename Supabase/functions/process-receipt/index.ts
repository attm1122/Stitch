import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

type ProcessReceiptRequest = {
  fileName: string;
  ocrText: string;
  pageCount?: number;
};

const ALLOWED_ORIGINS = (Deno.env.get("ALLOWED_ORIGINS") ?? "").split(",").filter(Boolean);

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

async function verifyJWT(authHeader: string | null): Promise<boolean> {
  if (!authHeader?.startsWith("Bearer ")) return false;

  const token = authHeader.slice(7);
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (!supabaseUrl || !supabaseServiceKey) return false;

  const client = createClient(supabaseUrl, supabaseServiceKey);
  const { data, error } = await client.auth.getUser(token);

  return !error && !!data.user;
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

  const isAuthorized = await verifyJWT(request.headers.get("Authorization"));
  if (!isAuthorized) {
    return Response.json({ error: "Unauthorized" }, { headers, status: 401 });
  }

  let body: ProcessReceiptRequest;
  try {
    body = (await request.json()) as ProcessReceiptRequest;
  } catch {
    return Response.json({ error: "Invalid JSON body" }, { headers, status: 400 });
  }

  try {
    const result = parseReceipt(body.ocrText ?? "", body.fileName ?? "receipt", body.pageCount ?? 1);
    return Response.json(result, { headers, status: 200 });
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Unknown error" },
      { headers, status: 500 }
    );
  }
});

function parseReceipt(text: string, fallbackFileName: string, pageCount: number) {
  const merchant = parseMerchant(text, fallbackFileName);
  const amount = parseAmount(text);
  const purchaseDate = parseDate(text);
  const currencyCode = parseCurrency(text);

  let confidence = 0.2;
  if (merchant) confidence += 0.3;
  if (amount !== null) confidence += 0.3;
  if (purchaseDate) confidence += 0.2;

  return {
    merchant,
    amount,
    currencyCode,
    purchaseDate,
    confidence: Math.min(confidence, 1),
    pageCount,
    rawText: text,
  };
}

function parseMerchant(text: string, fallbackFileName: string): string {
  const lines = text
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean);

  for (const line of lines.slice(0, 10)) {
    if (line.length < 3) continue;
    if (/tax invoice/i.test(line)) continue;
    if (/receipt/i.test(line)) continue;
    if (/\d/.test(line) && (line.match(/[a-z]/gi) ?? []).length < 3) continue;
    return line;
  }

  return fallbackFileName.replace(/\.[^.]+$/, "").replace(/[_-]/g, " ");
}

function parseAmount(text: string): number | null {
  const matches = [...text.matchAll(/(?:USD|EUR|GBP|AUD|CAD|\$|€|£)\s?(\d{1,4}(?:[.,]\d{3})*(?:[.,]\d{2}))/gi)];
  const values = matches
    .map((match) => Number(match[1].replaceAll(",", "")))
    .filter((value) => Number.isFinite(value) && value > 0);

  return values.length ? Math.max(...values) : null;
}

function parseDate(text: string): string | null {
  const patterns = [
    /\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b/g,
    /\b\d{4}[/-]\d{1,2}[/-]\d{1,2}\b/g,
  ];

  for (const pattern of patterns) {
    const match = text.match(pattern)?.[0];
    if (!match) continue;

    const parsed = new Date(match);
    if (!Number.isNaN(parsed.getTime()) && parsed.getFullYear() >= 2000) {
      return parsed.toISOString().slice(0, 10);
    }
  }

  return null;
}

function parseCurrency(text: string): string {
  const upper = text.toUpperCase();
  if (upper.includes("AUD")) return "AUD";
  if (upper.includes("EUR") || upper.includes("€")) return "EUR";
  if (upper.includes("GBP") || upper.includes("£")) return "GBP";
  if (upper.includes("CAD")) return "CAD";
  return "USD";
}
