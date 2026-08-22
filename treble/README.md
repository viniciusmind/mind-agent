# Agente Inbound de Vendas — Treble + Supabase

Agente de vendas do Mind Summit 2026 no WhatsApp. O Treble transporta as
mensagens; o cérebro é a Edge Function `treble-inbound-agent`, que consulta
o Supabase (fonte da verdade) a cada turno.

Comece por [`docs/00_PROJECT_STATE.md`](docs/00_PROJECT_STATE.md).

| Pasta | Conteúdo |
|---|---|
| `docs/` | estado, arquitetura, requisitos, decisões, testes, backlog, plano |
| `prompts/` | prompt principal do agente, versionado |
| `knowledge/` | base de fallback **gerada por script** a partir do Supabase (nunca editar à mão) |
| `integrations/` | contratos e roteiros: Treble (webhook, fluxo), Eduzz, HubSpot |
| `tests/` | suite executável dos casos de `docs/04_TESTS.md` |
