# Correspondência de preços e lotes → `mind.offers`

> Carga em 2026-08-21, corrigida no mesmo dia após a Adriana apontar a
> fonte da verdade: projeto Supabase **mind-summit-propostas**
> (`rwqdperfphubzteckyqd`) — tabelas `lotes`, `lote_precos`,
> `ticket_categories` (com os checkouts) e `pricing_tiers`. É a mesma
> fonte que alimenta o site via Edge Function `pricing`.
> O catálogo `eduzz_products` do vendas-dashboard serviu de validação
> cruzada (preços batem; o calendário de lá estava desatualizado).

## O mapeamento

| Origem (mind-summit-propostas) | Destino (`mind.offers`) |
|---|---|
| `ticket_categories.slug` (mind/vip/prime) | `codigo` = `{categoria}-lote-{n}` · `elegibilidade.categoria` |
| `lotes.numero` + `inicio`/`fim` | sufixo do `codigo` · `inicia_em`/`encerra_em` |
| `lote_precos.preco` | `valor` (BRL) |
| `lote_precos.parcela` (12x) | `condicoes_pagamento` = "12x de R$ N" |
| `ticket_categories.checkout_url` | `checkout_url` (link fixo por categoria — a Eduzz vira o lote no mesmo link) |

Checkouts: Mind `sun.eduzz.com/89AQDKYGWD` · VIP `sun.eduzz.com/40Q3EKPK0B`
· Prime `sun.eduzz.com/E05XKB2KWX`.

## Lote vigente e calendário (reestruturado em 19/08)

Regra da fonte: vigente = primeiro lote cujo `fim > now()`.
**Hoje: Lote 5** (14/08 → **28/08**) — Mind **R$ 1.597** (12x 133) ·
VIP **R$ 2.597** (12x 216) · Prime **R$ 6.297** (12x 525).
Depois: Lote 6 (28/08 → 04/09, Mind 1.697 · VIP 2.697) e Lote 7
(04/09 → 17/09). Argumento de urgência verdadeiro: **28/08 os preços sobem**.

## Grupos e volume

- `pricing_tiers` (global, no carrinho): 5–9 → 10% · 10–14 → 20% ·
  15–19 → 30% · 20+ → 35%. Gravado em
  `mind.commercial_rules.desconto_por_volume` com `acao: handoff_vendedor`.
- Produtos Eduzz "Grupo VIP" (5–9: R$250 off · 10+: R$500 off por pessoa)
  também existem e estão em `mind.offers` (`publico=false`, sem checkout —
  grupo fecha com vendedor).

## Sincronização contínua (construída em 2026-08-21) ✅

`mind.offers` acompanha a fonte sozinha, sem passo manual:

```
pg_cron (a cada 30 min, projeto mind-agent)
  → Edge Function mindagent-sync-precos
    → GET pricing (endpoint público do mind-summit-propostas)
    → sanidade por lote (mind < vip ≤ prime, valores positivos)
    → RPC mindagent_sync_offers (upsert de ofertas + tiers, marca vigente)
```

- Código versionado: `supabase/functions/mindagent-sync-precos/index.ts`
  e `supabase/migrations/20260821_sync_precos_lotes.sql`.
- Guardrail: lote com preços incoerentes é **pulado e reportado**; se a
  incoerência for no lote vigente, a sync inteira aborta (HTTP 422) e
  mantém os dados anteriores — nunca grava lixo por cima da verdade.
- Testada de ponta a ponta: 18 ofertas sincronizadas (lotes 2–7),
  vigente = 5, zero anomalias. Lote 7 veio correto da fonte
  (Mind 1.797 · VIP 2.797) — a suspeita de troca registrada antes era
  erro de leitura manual, retirada.
- Editar preço/lote no mind-summit-propostas é o único gesto necessário;
  em até 30 min o bot reflete.

## Pendências (para a Adriana confirmar)

1. **Dois mecanismos de desconto de grupo convivem** (tiers percentuais ×
   produtos "Grupo VIP" com valor fixo). Qual o bot deve citar?
2. `settings.event_date` diz `2026-09-01`, mas o evento é 16–17/09 —
   conferir o que esse campo significa para o site.
