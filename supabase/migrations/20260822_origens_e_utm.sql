-- Origem da conversa = o botão que a pessoa clicou (correção da Adriana).
--
-- O botão é conceito de primeira classe porque decide três coisas de uma vez:
--   1. utm_source  → qual SITE originou (mindsummit / institute / dash)
--   2. campo oculto do formulário do HubSpot (campo + valor)
--   3. a mensagem com que o bot abre a conversa
--
-- E o canal decide o utm_medium: Treble = `chatbot`,
-- concierge do site = `chatbot_concierge`.
--
-- Aplicada em 2026-08-22 no projeto ymnmotgglsrxmjmonwjz.
-- A tabela nasce VAZIA de propósito: a lista de botões por site é conteúdo
-- aprovado pela Adriana, não inventado aqui.

create table if not exists mind.origens (
  codigo text primary key,
  site text not null check (site in ('mindsummit','institute','dash','outro')),
  botao_rotulo text,
  descricao text,
  mensagem_abertura text,
  hubspot_campo text,
  hubspot_valor text,
  audiencia_sugerida text
    check (audiencia_sugerida in ('b2c','b2b','cliente_suporte','ja_comprou','desconhecido')),
  ativo boolean not null default true,
  atualizado_em timestamptz not null default now()
);

comment on table mind.origens is
  'Botões de entrada por site. Fonte única do utm_source, do campo oculto do HubSpot e da mensagem de abertura do bot.';

alter table treble.conversations
  add column if not exists origem_codigo text references mind.origens(codigo);

-- Versões antigas (utm_source fixo em "whatsapp"/"site") saem de cena para
-- não conviverem com as novas — overload silencioso é bug esperando data.
drop function if exists public.mind_material_link(text, text, text, text);
drop function if exists public.mind_materiais_para(text, text, text);
drop function if exists public.treble_materiais(text);
drop function if exists public.treble_agent_context(text);
drop function if exists public.treble_agent_start(text, jsonb);

create or replace function public.mind_material_link(
  p_url text,
  p_codigo text,
  p_utm_campaign text,
  p_canal text,
  p_origem text default null
) returns text
language sql stable security definer set search_path = public, mind
as $$
  select p_url
      || case when position('?' in p_url) > 0 then '&' else '?' end
      -- utm_source = o site de onde a pessoa veio; sem origem conhecida, "mind"
      || 'utm_source=' || coalesce(
           (select o.site from mind.origens o where o.codigo = p_origem), 'mind')
      -- utm_medium = o canal onde o agente conversa
      || '&utm_medium=' || case p_canal
            when 'whatsapp_treble' then 'chatbot'
            when 'site_concierge'  then 'chatbot_concierge'
            else p_canal end
      || '&utm_campaign=' || coalesce(nullif(p_utm_campaign,''), p_codigo)
      -- utm_content = o botão, para saber qual entrada gera conversa e venda
      || '&utm_content=' || coalesce(nullif(p_origem,''), 'sem_origem');
$$;
revoke all on function public.mind_material_link(text, text, text, text, text)
  from public, anon, authenticated;

create or replace function public.mind_materiais_para(
  p_canal text default 'whatsapp_treble',
  p_audiencia text default 'desconhecido',
  p_icp text default null,
  p_origem text default null
) returns jsonb
language sql security definer set search_path = public, mind
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'titulo', m.titulo, 'tipo', m.tipo,
           'sobre_o_que_e', m.conteudo_resumo,
           'quando_usar', m.quando_usar,
           'objecoes_que_quebra', m.objecoes_que_quebra,
           'link', public.mind_material_link(m.url, m.codigo, m.utm_campaign, p_canal, p_origem)
         ) order by m.ordem), '[]'::jsonb)
  from mind.materiais m
  where m.ativo
    and (coalesce(p_audiencia,'desconhecido') = any(m.audiencias))
    and (cardinality(m.icp) = 0 or p_icp is null or p_icp = any(m.icp));
$$;
revoke all on function public.mind_materiais_para(text, text, text, text)
  from public, anon, authenticated;

create or replace function public.treble_materiais(
  p_audience text default 'desconhecido',
  p_origem text default null
) returns jsonb
language sql security definer set search_path = public, mind
as $$ select public.mind_materiais_para('whatsapp_treble', p_audience, null, p_origem) $$;
revoke all on function public.treble_materiais(text, text) from public, anon, authenticated;

-- Ficha da origem: o que o bot precisa saber sobre o botão clicado.
create or replace function public.mind_origem(p_codigo text)
returns jsonb
language sql stable security definer set search_path = public, mind
as $$
  select case when p_codigo is null then null else (
    select jsonb_build_object(
      'codigo', o.codigo,
      'site', o.site,
      'botao', o.botao_rotulo,
      'descricao', o.descricao,
      'mensagem_abertura', o.mensagem_abertura,
      'hubspot', case when o.hubspot_campo is null then null
                      else jsonb_build_object('campo', o.hubspot_campo, 'valor', o.hubspot_valor) end,
      'audiencia_sugerida', o.audiencia_sugerida)
    from mind.origens o
    where o.codigo = p_codigo and o.ativo
  ) end;
$$;
-- O site precisa ler isto para preencher o campo oculto do formulário:
-- é configuração de marketing, não dado de lead.
grant execute on function public.mind_origem(text) to anon, authenticated;

create or replace function public.treble_agent_context(
  p_audience text default 'desconhecido',
  p_origem text default null
) returns jsonb
language sql security definer set search_path = public, mind, treble
as $$
select public.treble_agent_context_base() || jsonb_build_object(
    'momento', public.treble_momento(),
    'origem_da_conversa', public.mind_origem(p_origem),
    'materiais_que_posso_enviar', public.treble_materiais(p_audience, p_origem)
  )
$$;
revoke all on function public.treble_agent_context(text, text)
  from public, anon, authenticated;

-- start passa a registrar de qual botão veio a conversa (primeira gravação
-- vence: a origem é da entrada, não de um turno qualquer no meio).
create or replace function public.treble_agent_start(
  p_session_external_id text,
  p_contact jsonb default '{}'::jsonb,
  p_origem text default null
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

  insert into treble.conversations
    (session_external_id, nome_contato, telefone, telefone_hash, origem_codigo)
  values (
    p_session_external_id,
    nullif(trim(coalesce(p_contact->>'nome','')),''),
    nullif(trim(coalesce(p_contact->>'telefone','')),''),
    nullif(trim(coalesce(p_contact->>'telefone_hash','')),''),
    (select o.codigo from mind.origens o where o.codigo = nullif(trim(coalesce(p_origem,'')),''))
  )
  on conflict (session_external_id) do update
    set ultima_atividade = now(),
        nome_contato = coalesce(treble.conversations.nome_contato, excluded.nome_contato),
        telefone = coalesce(treble.conversations.telefone, excluded.telefone),
        telefone_hash = coalesce(treble.conversations.telefone_hash, excluded.telefone_hash),
        origem_codigo = coalesce(treble.conversations.origem_codigo, excluded.origem_codigo)
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
    'origem_codigo', conv.origem_codigo,
    'historico', hist
  );
end;
$$;
revoke all on function public.treble_agent_start(text, jsonb, text)
  from public, anon, authenticated;
