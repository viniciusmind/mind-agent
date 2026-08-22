# Plano de execução — adaptado da "ordem de amanhã"

A ordem original (55 itens) foi mantida na disciplina — checkpoints,
"não abrir o Treble antes de decidir", P0–P3, congelar v0.1 — e adaptada
nas partes que assumiam a arquitetura antiga (ver D-1, D-2, D-5 em
`03_DECISIONS.md`). Itens 1–26 (decidir) estão **concluídos** com estes
documentos.

## Checkpoints obrigatórios (mantidos)

1. **Antes de construir**: arquitetura entendida e congelada ✅ (`01_ARCHITECTURE.md`)
2. **Antes de conectar o Treble**: cérebro + Supabase funcionando isolados
3. **Antes de encerrar**: end-to-end no WhatsApp + casos críticos passando

## Fase 1 — Dados (Claude, sem dependências)

- [x] Estruturas criadas (2026-08-21, ver D-12): schema `treble`
      (conversations + messages), `mind.coupons`, `mind.commercial_rules`
      com defaults seguros; ingressos usam `mind.offers` (já existia),
      FAQ usa `mind.organization_content`
      (migration `supabase/migrations/20260821_treble_inbound_mvp.sql`)
- [x] `mind.offers` populada (2026-08-21): 22 ofertas mapeadas do catálogo
      Eduzz do projeto vendas-dashboard — categoria × lote com preço,
      grupos VIP e viradas; Lote 5 vigente (confirmado pelas vendas).
      Detalhes e pendências em `../integrations/eduzz.md`
- [ ] Ainda **precisa da Adriana**: validar 1 link `sun.eduzz.com`, regras
      comerciais reais (→ `mind.commercial_rules`), cupons (→ `mind.coupons`),
      FAQ, preços dos upgrades (inconsistentes no catálogo)
- [ ] Validar na mão: "preço atual do VIP?", "checkout do PRIME?",
      "cupom X vale?" — direto no banco, sem IA

## Fase 2 — Cérebro (Claude)

- [ ] Edge Function `treble-inbound-agent`: webhook + LLM + tools internas
      + guardrails + gravação em `conversations`
- [ ] Prompt principal em `prompts/` (missão, contexto, política de
      decisão, uso de tools, limites, handoff, tom, exemplos) —
      tom de voz definitivo **precisa do material da Adriana**
- [ ] Suite de testes em `tests/` com os 13 casos de `04_TESTS.md`
- [ ] **Checkpoint 2**: casos críticos passando contra a função isolada

## Fase 3 — Treble (Adriana no painel, com roteiro pronto do Claude)

- [ ] Guardar secrets: `TREBLE_API_KEY` (painel → Developers) e
      `TREBLE_WEBHOOK_SECRET` nas env vars da Edge Function
- [ ] Montar o fluxo fino no Conversation Builder: entrada → salvar
      resposta → webhook → `[REQUEST_TRIGGER]` → entrega → rotas fixas de
      handoff (inbox vendedores) e opt-out
      (roteiro passo a passo em `integrations/treble.md`)
- [ ] Configurar variáveis de sessão espelhadas
- [ ] Teste end-to-end: WhatsApp → Treble → cérebro → Supabase → resposta

## Fase 4 — Validação e v0.1

- [ ] Rodar os 13 casos pelo WhatsApp real
- [ ] Classificar P0–P3; corrigir só P0/P1; regressão completa após cada fix
- [ ] Atualizar `00_PROJECT_STATE`, `04_TESTS` (resultados), `03_DECISIONS`
- [ ] Gerar base de fallback (`knowledge/`) e subir no agente nativo
- [ ] Congelar **v0.1** (tag no GitHub) e parar — sem outbound no mesmo dia

## Divergências da ordem original (rastreabilidade)

| Itens originais | O que mudou |
|---|---|
| 1 (repo novo) | pasta `treble/` no `mind-agent` (D-5) |
| 19, 23, 30–32 (Intelligence API HTTP) | tools internas na Edge Function; API pública vai ao backlog (D-2) |
| 27 (projeto Supabase novo) | reusa `mind-agent`, que já tem agenda/palestrantes (D-5) |
| 36 (conhecimento estático no Treble) | tudo no Supabase; Treble nativo só como fallback gerado (D-6) |
| 37–38 (API tools no agente do Treble) | substituídos pelo webhook + `[REQUEST_TRIGGER]` (D-1) |
