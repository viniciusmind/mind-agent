# Arquitetura — Agente Inbound de Vendas (Treble)

> Congelada em 2026-08-21 (Checkpoint 1). Mudanças exigem registro em
> `03_DECISIONS.md`.

## North Star

O agente existe para **transformar conversas inbound em vendas concluídas
do Mind Summit**, com informação sempre correta (fonte: Supabase) e sem
jamais violar as regras comerciais. Toda conversa termina em um desfecho
mensurável.

## Visão geral

```
WhatsApp
   │
Treble  ─ fluxo fino: entrada → webhook → entrega → (handoff | opt-out)
   │  webhook de resposta / [REQUEST_TRIGGER]
   ▼
Edge Function `treble-inbound-agent`   ← o cérebro
   │  LLM + tools internas (funções no mesmo processo)
   ▼
Supabase (projeto mind-agent) ── fonte da verdade
   tickets · coupons · commercial_rules · faq · event_info
   conversations · agenda/palestrantes (já existentes)
   │
   ├─ Eduzz ………… status de compra, abandono (um checkout por categoria)
   ├─ HubSpot ……… lead qualificado, objeção, desfecho
   └─ Inbox Treble … handoff para os vendedores
```

## O contrato com o Treble

Mecanismo oficial documentado pelo Treble ("Integrate Your Own AI"):

1. O bloco de mensagem do fluxo salva a resposta do usuário em variável e
   dispara o **webhook de resposta** para a Edge Function, com corpo
   contendo mensagem, variáveis e `session_external_id`.
2. Resposta em **menos de 10 s** → devolvemos no próprio webhook.
3. Processamento mais longo → o fluxo usa o bloco **`[REQUEST_TRIGGER]`**:
   o Treble pausa a conversa e espera nosso
   `POST /session/{session_external_id}/update`, que devolve a resposta e
   atualiza `user_session_keys`.
4. Variáveis de sessão espelhadas no Treble (mínimas): `intent`,
   `stage`, `needs_human`, `checkout_sent`. O estado completo vive na
   tabela `conversations`.

## O cérebro: `treble-inbound-agent`

Uma única Edge Function que, a cada turno:

1. Carrega a conversa (`conversations`) e o contexto do lead.
2. Chama o LLM com o prompt principal (`prompts/`) e as **tools internas**:
   `get_ticket_info`, `get_speakers`, `get_event_info`,
   `get_checkout_link`, `check_coupon`, `get_commercial_rule`,
   `check_purchase_status` (via API Eduzz), `request_handoff`.
   Tools são funções no mesmo processo consultando o banco direto —
   sem HTTP intermediário, sem "esquecer de consultar".
3. Aplica os **guardrails em código** (ver abaixo).
4. Grava turno, `stage` e sinais comerciais em `conversations`.
5. Devolve a resposta ao Treble.

### Guardrails em código, não em prompt

Decisões comerciais sensíveis são determinísticas:

- Cupom/desconto: o LLM **pergunta** a `get_commercial_rule()` se pode;
  a função lê `commercial_rules` e responde sim/não com o texto permitido.
- Preço e link de checkout: sempre da tabela, nunca da memória do modelo.
  Resposta com preço sem tool call correspondente é bloqueada e refeita.
- O prompt governa o *como falar*; o código governa o *o que é permitido*.

## Dados

### Tabelas novas (MVP)

| Tabela | Conteúdo | Muda com que frequência |
|---|---|---|
| `tickets` | categorias MIND/VIP/PRIME: preço vigente, lote, disponibilidade, benefícios, link de checkout | semanal/diária |
| `coupons` | código, desconto, validade, elegibilidade, ativo | diária |
| `commercial_rules` | regras de oferta: quando pode desconto, argumentos permitidos, limites | eventual |
| `faq` | perguntas estáveis com resposta canônica | eventual |
| `event_info` | data, local, horários, políticas (reembolso, transferência, NF) | raro |
| `conversations` | transcript, variáveis, `stage`, desfecho, sinais (objeção, interesse) | contínua |

Agenda e palestrantes **não são duplicados**: o cérebro consome a mesma
fonte do `mindagent-bootstrap`.

### Conhecimento estático × mutável

Com o cérebro dentro do Supabase, a distinção deixa de ser arquitetural —
tudo vive em tabelas. Ela sobrevive só em dois lugares:

- `faq`/`event_info` (estável) × `tickets`/`coupons` (vivo), por higiene
  de atualização;
- o **fallback**: `knowledge/` guarda um documento gerado por script a
  partir do Supabase, para subir como base de conhecimento do agente
  nativo do Treble — plano B se a Edge Function cair. Nunca editado à mão.

## Desfechos (todo encerramento grava um)

`compra_concluida` · `checkout_enviado` · `lead_qualificado` ·
`handoff_humano` · `ja_comprou` · `descadastrado` · `abandono`

## Segurança

- Secrets só em variáveis de ambiente da Edge Function:
  `TREBLE_API_KEY`, `OPENAI_API_KEY` (ou provedor escolhido),
  `TREBLE_WEBHOOK_SECRET` para validar a origem das chamadas.
- `conversations` com RLS; acesso só via service role da função.
- Dados pessoais do lead: mínimo necessário, mascarados em logs
  (mesmo padrão do `mindagent-chat`).

## O que fica fora da V1

Ver `05_BACKLOG.md`: outbound, carrinho abandonado ativo, agentes
especializados, Mind Intelligence API como camada pública para outras
superfícies (AI Coach, app), RAG sobre conteúdo longo.
