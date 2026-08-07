import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const authHeader = request.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return json({ error: "Authentication required" }, 401);

  const admin = createClient(supabaseUrl, serviceRoleKey);
  const token = authHeader.slice("Bearer ".length);
  const { data: userData, error: userError } = await admin.auth.getUser(token);
  if (userError || !userData.user) return json({ error: "Invalid session" }, 401);

  if (request.method === "GET") {
    const { data, error } = await admin
      .from("leaderboard_scores")
      .select("player_name, score, duration_seconds, created_at")
      .order("score", { ascending: false })
      .order("created_at", { ascending: true })
      .limit(10);
    if (error) return json({ error: "Could not load scores" }, 500);
    return json(data ?? []);
  }

  if (request.method === "POST") {
    const payload = await request.json().catch(() => null);
    const playerName = typeof payload?.player_name === "string" ? payload.player_name.trim().slice(0, 12) : "";
    const score = Number(payload?.score);
    const duration = Number(payload?.duration);
    if (!playerName || !Number.isInteger(score) || score < 0 || score > 1_000_000 || !Number.isFinite(duration) || duration < 0 || duration > 3600) {
      return json({ error: "Invalid score submission" }, 400);
    }

    // A lightweight sanity bound keeps obviously fabricated scores out while
    // preserving the jam's client-side Near Miss scoring model.
    if (score > Math.ceil(duration * 10 * 10 + 5000)) return json({ error: "Score exceeds a plausible Run" }, 422);

    const { error } = await admin.from("leaderboard_scores").insert({
      player_id: userData.user.id,
      player_name: playerName,
      score,
      duration_seconds: duration,
    });
    if (error) return json({ error: "Could not save score" }, 500);
    return json({ ok: true });
  }

  return json({ error: "Method not allowed" }, 405);
});
