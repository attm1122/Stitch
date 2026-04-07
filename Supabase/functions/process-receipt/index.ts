import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

type ProcessReceiptRequest = {
  fileName: string;
  ocrText: string;
  pageCount?: number;
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
    const body = (await request.json()) as ProcessReceiptRequest;
    const result = parseReceipt(body.ocrText ?? "", body.fileName ?? "receipt", body.pageCount ?? 1);

    return Response.json(result, {
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

function parseMerchant(text: string, fallbackFileName: string) {
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

function parseAmount(text: string) {
  const matches = [...text.matchAll(/(?:USD|EUR|GBP|AUD|CAD|\$|€|£)\s?(\d{1,4}(?:[.,]\d{3})*(?:[.,]\d{2}))/gi)];
  const values = matches
    .map((match) => Number(match[1].replaceAll(",", "")))
    .filter((value) => Number.isFinite(value));

  return values.length ? Math.max(...values) : null;
}

function parseDate(text: string) {
  const patterns = [
    /\b\d{1,2}[/-]\d{1,2}[/-]\d{2,4}\b/g,
    /\b\d{4}[/-]\d{1,2}[/-]\d{1,2}\b/g,
  ];

  for (const pattern of patterns) {
    const match = text.match(pattern)?.[0];
    if (!match) continue;

    const parsed = new Date(match);
    if (!Number.isNaN(parsed.getTime())) {
      return parsed.toISOString().slice(0, 10);
    }
  }

  return null;
}

function parseCurrency(text: string) {
  const upper = text.toUpperCase();
  if (upper.includes("AUD")) return "AUD";
  if (upper.includes("EUR") || upper.includes("€")) return "EUR";
  if (upper.includes("GBP") || upper.includes("£")) return "GBP";
  if (upper.includes("CAD")) return "CAD";
  return "USD";
}

