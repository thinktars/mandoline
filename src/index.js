// Mandoline site Worker: serves the static assets in ./web and captures
// download signups (email + request context) into the D1 `signups` table.

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

async function handleSignup(request, env) {
  // Guard against oversized bodies.
  const raw = await request.text();
  if (raw.length > 2000) return json({ ok: false, error: "Payload too large." }, 413);

  let body;
  try {
    body = JSON.parse(raw || "{}");
  } catch {
    return json({ ok: false, error: "Invalid request." }, 400);
  }

  const email = String(body.email || "").trim().toLowerCase();
  if (!email || email.length > 254 || !EMAIL_RE.test(email)) {
    return json({ ok: false, error: "Please enter a valid email address." }, 422);
  }

  const cf = request.cf || {};
  const meta = {
    user_agent: request.headers.get("user-agent") || null,
    referrer: (typeof body.referrer === "string" ? body.referrer.slice(0, 500) : null) ||
      request.headers.get("referer") || null,
    country: cf.country || null,
    city: cf.city || null,
    region: cf.region || null,
    source: (typeof body.source === "string" ? body.source.slice(0, 60) : null) || "download_modal",
  };

  try {
    await env.DB.prepare(
      `INSERT INTO signups (email, user_agent, referrer, country, city, region, source)
       VALUES (?, ?, ?, ?, ?, ?, ?)`
    )
      .bind(email, meta.user_agent, meta.referrer, meta.country, meta.city, meta.region, meta.source)
      .run();
  } catch (err) {
    console.error("signup insert failed", err);
    return json({ ok: false, error: "Could not save your email. Please try again." }, 500);
  }

  return json({ ok: true });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/api/signup") {
      if (request.method !== "POST") {
        return json({ ok: false, error: "Method not allowed." }, 405);
      }
      return handleSignup(request, env);
    }

    // Everything else is a static asset (served by the assets binding).
    return env.ASSETS.fetch(request);
  },
};
