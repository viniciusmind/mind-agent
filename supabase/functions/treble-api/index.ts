// Ponte de diagnóstico/operação com a API do Treble.
// Usa o secret TREBLE_API_KEY (nunca exposto na resposta) e devolve a
// resposta CRUA do Treble — serve para descobrir por que um disparo não
// chegou (template não aprovado, poll inválido, número recusado...).
//
// Protegida pelo mesmo token do webhook do agente (?token=...).

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.112.3";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
  if (req.method !== "POST") return json(405, { ok: false, error: "method_not_allowed" });

  const url = new URL(req.url);
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  const { data: cfg } = await supabase.rpc("treble_agent_config");
  if (!cfg?.webhook_token) return json(503, { ok: false, error: "config_indisponivel" });
  if (url.searchParams.get("token") !== cfg.webhook_token) return json(401, { ok: false, error: "unauthorized" });

  const apiKey = Deno.env.get("TREBLE_API_KEY") ?? "";
  if (!apiKey) return json(503, { ok: false, error: "treble_api_key_ausente", dica: "cadastrar TREBLE_API_KEY nos secrets das Edge Functions" });

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json(400, { ok: false, error: "invalid_json" });
  }

  const pollId = String(body.poll_id ?? "").trim();
  const cellphone = String(body.cellphone ?? "").replace(/\D/g, "");
  const countryCode = String(body.country_code ?? "+55").trim();
  const sessionKeys = Array.isArray(body.user_session_keys) ? body.user_session_keys : [];

  if (!pollId || !cellphone) {
    return json(422, { ok: false, error: "faltam_campos", detalhe: "informe poll_id e cellphone" });
  }

  const endpoint = `https://main.treble.ai/deployment/api/poll/${encodeURIComponent(pollId)}`;
  const payload = {
    users: [{ cellphone, country_code: countryCode, user_session_keys: sessionKeys }],
  };

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 15000);
  try {
    const res = await fetch(endpoint, {
      method: "POST",
      headers: { "Authorization": apiKey, "Content-Type": "application/json" },
      body: JSON.stringify(payload),
      signal: controller.signal,
    });
    const texto = await res.text();
    let corpo: unknown;
    try { corpo = JSON.parse(texto); } catch { corpo = texto.slice(0, 1500); }

    console.info(JSON.stringify({ fn: "treble-api", endpoint, status: res.status }));
    return json(200, { ok: res.ok, treble_status: res.status, treble_resposta: corpo, endpoint });
  } catch (e) {
    const isTimeout = e instanceof DOMException && e.name === "AbortError";
    return json(200, { ok: false, error: isTimeout ? "timeout" : "falha_de_rede", endpoint });
  } finally {
    clearTimeout(timeout);
  }
});
