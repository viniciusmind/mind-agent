// Sincroniza mind.offers com a fonte da verdade de preços/lotes:
// a Edge Function pública `pricing` do projeto mind-summit-propostas.
// Disparada pelo pg_cron a cada 30 min (e manualmente, se preciso).
//
// verify_jwt=false de propósito: o efeito é idempotente e a fonte é
// fixa — o pior que um chamador estranho consegue é re-sincronizar.
// Guardrail: lote com preços incoerentes (mind >= vip, valores ausentes
// ou não positivos) é PULADO e reportado, nunca gravado.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const PRICING_URL = "https://rwqdperfphubzteckyqd.supabase.co/functions/v1/pricing";

function json(status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
}

function loteSano(precos: Record<string, unknown>): boolean {
  const mind = Number(precos?.mind);
  const vip = Number(precos?.vip);
  const prime = Number(precos?.prime);
  if (![mind, vip, prime].every((v) => Number.isFinite(v) && v > 0)) return false;
  return mind < vip && vip <= prime;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST" && req.method !== "GET") {
    return json(405, { ok: false, error: "method_not_allowed" });
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8000);
  try {
    const res = await fetch(PRICING_URL, { signal: controller.signal });
    if (!res.ok) {
      console.error(JSON.stringify({ fn: "sync-precos", erro: "fonte_http_" + res.status }));
      return json(502, { ok: false, error: "fonte_indisponivel" });
    }
    const fonte = await res.json();

    const vigente = fonte?.lote?.numero;
    const lotes = Array.isArray(fonte?.lotes) ? fonte.lotes : [];
    const tiers = Array.isArray(fonte?.tiers) ? fonte.tiers : [];
    if (!Number.isInteger(vigente) || lotes.length === 0) {
      console.error(JSON.stringify({ fn: "sync-precos", erro: "payload_invalido" }));
      return json(502, { ok: false, error: "payload_invalido" });
    }

    const anomalias: number[] = [];
    const validos = lotes.filter((l: { numero?: number; precos?: Record<string, unknown> }) => {
      if (loteSano(l?.precos ?? {})) return true;
      if (Number.isInteger(l?.numero)) anomalias.push(l.numero as number);
      return false;
    });

    if (anomalias.includes(vigente)) {
      // Nunca sincronizar por cima do lote vigente com dados suspeitos.
      console.error(JSON.stringify({ fn: "sync-precos", erro: "vigente_anomalo", lote: vigente }));
      return json(422, { ok: false, error: "lote_vigente_com_precos_incoerentes", lote: vigente });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const { data, error } = await supabase.rpc("mindagent_sync_offers", {
      p_vigente: vigente,
      p_lotes: validos,
      p_tiers: tiers,
    });
    if (error) {
      console.error(JSON.stringify({ fn: "sync-precos", erro: "rpc", detalhe: error.message }));
      return json(500, { ok: false, error: "rpc_falhou" });
    }

    const resumo = { ok: true, ...data, lotes_pulados_por_anomalia: anomalias };
    console.info(JSON.stringify({ fn: "sync-precos", ...resumo }));
    return json(200, resumo);
  } catch (e) {
    const isTimeout = e instanceof DOMException && e.name === "AbortError";
    console.error(JSON.stringify({ fn: "sync-precos", erro: isTimeout ? "timeout" : "inesperado" }));
    return json(isTimeout ? 504 : 500, { ok: false, error: isTimeout ? "timeout" : "erro_inesperado" });
  } finally {
    clearTimeout(timeout);
  }
});
