-- Cérebro v0.1 do agente inbound (Treble): config com token do webhook
-- e RPCs de acesso (schemas mind/treble não são expostos ao PostgREST;
-- todo acesso da Edge Function passa por estas funções, service role).
-- Aplicada em 2026-08-21 (migration "treble_agent_v01").

create table treble.config (
  chave text primary key,
  valor text not null,
  atualizado_em timestamptz not null default now()
);
alter table treble.config enable row level security;
comment on table treble.config is 'Configuração do agente (ex.: token do webhook). Só service role.';

insert into treble.config (chave, valor)
values ('webhook_token', encode(gen_random_bytes(24), 'hex'));

-- Token do webhook (validação da origem das chamadas do Treble)
create or replace function public.treble_agent_token() returns text
language sql security definer set search_path = public, treble
as $$ select valor from treble.config where chave = 'webhook_token' $$;
revoke all on function public.treble_agent_token() from public, anon, authenticated;

-- Abre/recupera a conversa e devolve histórico recente
create or replace function public.treble_agent_start(
  p_session_external_id text,
  p_contact jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path = public, treble
as $$
declare
  conv treble.conversations;
  hist jsonb;
begin
  if p_session_external_id is null or length(p_session_external_id) < 3 then
    raise exception 'session_external_id inválido';
  end if;

  insert into treble.conversations (session_external_id, nome_contato, telefone_hash)
  values (
    p_session_external_id,
    nullif(trim(coalesce(p_contact->>'nome','')),''),
    nullif(trim(coalesce(p_contact->>'telefone_hash','')),'')
  )
  on conflict (session_external_id) do update
    set ultima_atividade = now(),
        nome_contato = coalesce(treble.conversations.nome_contato, excluded.nome_contato)
  returning * into conv;

  select coalesce(jsonb_agg(jsonb_build_object('papel', m.papel, 'conteudo', m.conteudo)
                            order by m.criado_em), '[]'::jsonb)
    into hist
  from (select papel, conteudo, criado_em
          from treble.messages
         where conversation_id = conv.id
         order by criado_em desc limit 12) m;

  return jsonb_build_object(
    'conversation_id', conv.id,
    'audience', conv.audience,
    'stage', conv.stage,
    'variables', conv.variables,
    'nome_contato', conv.nome_contato,
    'historico', hist
  );
end;
$$;
revoke all on function public.treble_agent_start(text, jsonb) from public, anon, authenticated;

-- Contexto oficial que alimenta o LLM (fonte da verdade, nada de memória)
create or replace function public.treble_agent_context() returns jsonb
language sql security definer set search_path = public, mind
as $$
select jsonb_build_object(
  'evento', (select to_jsonb(e) - 'id' from mind.events e limit 1),
  'ofertas_vigentes', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'codigo', o.codigo, 'nome', o.nome, 'valor', o.valor,
      'condicoes_pagamento', o.condicoes_pagamento,
      'checkout_url', o.checkout_url,
      'lote_termina_em', o.encerra_em)), '[]'::jsonb)
    from mind.offers o where o.ativo and o.publico),
  'proximo_lote', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'codigo', o.codigo, 'valor', o.valor, 'comeca_em', o.inicia_em)), '[]'::jsonb)
    from mind.offers o
    where not o.ativo and o.inicia_em is not null and o.inicia_em > now()
      and o.inicia_em = (select min(i.inicia_em) from mind.offers i
                          where i.inicia_em > now() and not (i.elegibilidade ? 'grupo'))
      and not (o.elegibilidade ? 'grupo')),
  'regras_comerciais', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'chave', r.chave, 'descricao', r.descricao, 'config', r.config)), '[]'::jsonb)
    from mind.commercial_rules r where r.ativo),
  'politicas', (
    select coalesce(jsonb_agg(jsonb_build_object('titulo', p.titulo, 'texto', p.texto)), '[]'::jsonb)
    from mind.policies p where p.ativo),
  'faq', (
    select coalesce(jsonb_agg(jsonb_build_object('titulo', c.titulo, 'texto', c.corpo)), '[]'::jsonb)
    from (select titulo, corpo from mind.organization_content
           where ativo and categoria = 'faq' limit 20) c)
)
$$;
revoke all on function public.treble_agent_context() from public, anon, authenticated;

-- Grava o turno e o estado da conversa
create or replace function public.treble_agent_save_turn(
  p_conversation_id uuid,
  p_user_msg text,
  p_answer text,
  p_state jsonb,
  p_tool_calls jsonb default null
) returns void
language plpgsql security definer set search_path = public, treble
as $$
begin
  insert into treble.messages (conversation_id, papel, conteudo)
  values (p_conversation_id, 'lead', p_user_msg);

  insert into treble.messages (conversation_id, papel, conteudo, tool_calls)
  values (p_conversation_id, 'agente', p_answer, p_tool_calls);

  update treble.conversations set
    audience = coalesce(nullif(p_state->>'audience',''), audience),
    intent = coalesce(nullif(p_state->>'intent',''), intent),
    ticket_interest = coalesce(nullif(p_state->>'ticket_interest',''), ticket_interest),
    objection = coalesce(nullif(p_state->>'objection',''), objection),
    needs_human = coalesce((p_state->>'needs_human')::boolean, needs_human),
    checkout_sent = checkout_sent or coalesce((p_state->>'checkout_sent')::boolean, false),
    stage = coalesce(nullif(p_state->>'stage',''), stage),
    desfecho = coalesce(nullif(p_state->>'desfecho',''), desfecho),
    encerrada_em = case when nullif(p_state->>'desfecho','') is not null then now() else encerrada_em end,
    ultima_atividade = now()
  where id = p_conversation_id;
end;
$$;
revoke all on function public.treble_agent_save_turn(uuid, text, text, jsonb, jsonb) from public, anon, authenticated;
