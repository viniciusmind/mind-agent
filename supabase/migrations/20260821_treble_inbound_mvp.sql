-- Agente inbound de vendas no WhatsApp (Treble) — estruturas do MVP.
-- Aplicada em 2026-08-21 no projeto ymnmotgglsrxmjmonwjz (migration
-- "treble_inbound_mvp"). Reusa o que o schema mind já tem (offers =
-- ingressos, policies, event_rules, organization_content = FAQ);
-- cria só o que falta.

-- ============================================================
-- Schema treble: runtime das conversas do bot de vendas
-- ============================================================
create schema if not exists treble;

comment on schema treble is
  'Runtime do agente inbound de vendas no WhatsApp (Treble): conversas, mensagens e sinais. Acesso somente via service role das Edge Functions.';

create table treble.conversations (
  id uuid primary key default gen_random_uuid(),
  session_external_id text not null unique,
  telefone_hash text,
  nome_contato text,
  audience text not null default 'desconhecido'
    check (audience in ('b2c','b2b','cliente_suporte','ja_comprou','desconhecido')),
  intent text,
  ticket_interest text,
  objection text,
  coupon_status text,
  checkout_sent boolean not null default false,
  purchase_status text,
  needs_human boolean not null default false,
  stage text,
  desfecho text
    check (desfecho in ('compra_concluida','checkout_enviado','lead_qualificado',
                        'handoff_humano','ja_comprou','descadastrado','abandono')),
  variables jsonb not null default '{}'::jsonb,
  iniciada_em timestamptz not null default now(),
  ultima_atividade timestamptz not null default now(),
  encerrada_em timestamptz
);

comment on table treble.conversations is
  'Uma linha por conversa do WhatsApp; session_external_id vem do webhook do Treble. Conversa encerrada sem desfecho é bug do agente.';

create index conversations_atividade_idx on treble.conversations (ultima_atividade desc);
create index conversations_desfecho_idx on treble.conversations (desfecho);
create index conversations_audience_idx on treble.conversations (audience);

create table treble.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references treble.conversations(id) on delete cascade,
  papel text not null check (papel in ('lead','agente','vendedor','sistema')),
  conteudo text not null,
  tool_calls jsonb,
  criado_em timestamptz not null default now()
);

comment on table treble.messages is
  'Transcript por turno; tool_calls registra quais consultas o agente fez para responder (auditoria de preço/cupom).';

create index messages_conversa_idx on treble.messages (conversation_id, criado_em);

alter table treble.conversations enable row level security;
alter table treble.messages enable row level security;
-- Sem policies de propósito: só a service role (Edge Functions) acessa.

-- ============================================================
-- mind.coupons: cupons validáveis pelo agente
-- ============================================================
create table mind.coupons (
  id uuid primary key default gen_random_uuid(),
  event_id uuid references mind.events(id),
  codigo text not null unique,
  descricao text,
  tipo text not null check (tipo in ('percentual','valor_fixo')),
  valor numeric not null check (valor > 0),
  offer_codigo text,
  ativo boolean not null default false,
  valido_de timestamptz,
  valido_ate timestamptz,
  max_usos integer,
  condicoes jsonb not null default '{}'::jsonb,
  atualizado_em timestamptz not null default now()
);

comment on table mind.coupons is
  'Cupons que o agente pode validar. offer_codigo nulo = vale para qualquer categoria; ativo=false por default para cupom nunca nascer válido por acidente.';

alter table mind.coupons enable row level security;

-- ============================================================
-- mind.commercial_rules: guardrails comerciais legíveis por máquina
-- ============================================================
create table mind.commercial_rules (
  id uuid primary key default gen_random_uuid(),
  chave text not null unique,
  descricao text,
  config jsonb not null default '{}'::jsonb,
  ativo boolean not null default true,
  atualizado_em timestamptz not null default now()
);

comment on table mind.commercial_rules is
  'Regras que o agente CONSULTA antes de agir (código decide, prompt fala). config é o contrato legível por máquina de cada regra.';

alter table mind.commercial_rules enable row level security;

-- Defaults seguros: na ausência de regra explícita liberando, o agente
-- não oferece benefício. Valores reais entram com os dados comerciais.
insert into mind.commercial_rules (chave, descricao, config) values
  ('desconto_espontaneo',
   'O agente pode oferecer desconto por iniciativa própria?',
   '{"permitido": false}'),
  ('mencionar_cupom_nao_solicitado',
   'O agente pode mencionar cupom sem o lead perguntar?',
   '{"permitido": false}'),
  ('insistencia_apos_desinteresse',
   'Quantas retomadas após sinal claro de desinteresse?',
   '{"max_retomadas": 1}');
