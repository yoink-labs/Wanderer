import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type InvitePayload = {
  to?: string;
  tripTitle?: string;
  inviterName?: string;
  link?: string;
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const payload = (await req.json()) as InvitePayload;
    const to = payload.to?.trim();
    const tripTitle = payload.tripTitle?.trim() || "a trip";
    const inviterName = payload.inviterName?.trim() || "Someone";
    const link = payload.link?.trim();

    if (!to || !to.includes("@")) {
      return json({ error: "A valid recipient email is required." }, 400);
    }
    if (!link) {
      return json({ error: "An invite link is required." }, 400);
    }

    const apiKey = Deno.env.get("RESEND_API_KEY");
    if (!apiKey) {
      return json({ error: "RESEND_API_KEY is not configured for this project." }, 503);
    }

    const from = Deno.env.get("INVITE_FROM_EMAIL") ?? "Wanderer <onboarding@resend.dev>";

    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from,
        to: [to],
        subject: `${inviterName} invited you to ${tripTitle} on Wanderer`,
        html: `
          <div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#EFF1F3;padding:32px">
            <div style="max-width:520px;margin:0 auto;background:#fff;border-radius:16px;padding:28px">
              <p style="margin:0 0 8px;color:#D77A61;font-weight:600;letter-spacing:.08em;font-size:12px">WANDERER</p>
              <h1 style="margin:0 0 12px;color:#223843;font-size:24px">${escapeHtml(inviterName)} invited you to ${escapeHtml(tripTitle)}</h1>
              <p style="margin:0 0 22px;color:#5E6E76;line-height:1.5">Open the trip to see the day-by-day plan, bookings and notes.</p>
              <a href="${escapeHtml(link)}" style="display:inline-block;background:#223843;color:#fff;text-decoration:none;padding:12px 20px;border-radius:10px;font-weight:600">Open the trip</a>
              <p style="margin:22px 0 0;color:#8A969B;font-size:12px">If the button doesn't work, paste this link into your browser:<br>${escapeHtml(link)}</p>
            </div>
          </div>
        `,
      }),
    });

    const body = await response.json().catch(() => ({}));
    if (!response.ok) {
      return json({ error: body.message ?? "The email provider rejected the message." }, 502);
    }
    return json({ ok: true, id: body.id ?? null }, 200);
  } catch (error) {
    return json({ error: String(error) }, 500);
  }
});

function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}
