-- Atribuição ponta a ponta (Adriana, 2026-08-22): "é importante creditar a
-- UTM que trouxe ela pro site" e "se o bot mandar o link do carrinho, tem
-- que repassar essa UTM pro checkout da Eduzz".
--
-- O problema real: o WhatsApp quebra a cadeia — não existe query string
-- numa conversa. Então o site registra a UTM aqui, recebe um token curto e
-- manda só o token dentro do texto pré-preenchido do wa.me. O cérebro lê o
-- token na primeira mensagem, resolve, guarda na conversa, apaga o token do
-- texto (o lead não escreveu aquilo) e repassa a UTM original ao checkout.
--
-- Decisão que vale registrar: no checkout a UTM ORIGINAL vai intacta —
-- utm_source=google continua google. Se o bot sobrescrevesse com
-- "mindsummit", a mídia paga perderia o crédito da venda que ela gerou.
-- A camada do bot vai em parâmetros próprios (mind_canal, mind_origem,
-- mind_conversa), que não disputam com os utm_.

create table if not exists mind.utm_sessoes (
  token text primary key,
  site text,
  origem_codigo text references mind.origens(codigo),
  utm_source text, utm_medium text, utm_campaign text,
  utm_content text, utm_term text,
  gclid text, fbclid text,
  referrer text, landing_url text,
  criado_em timestamptz not null default now(),
  usado_em timestamptz
);
create index if not exists utm_sessoes_criado_idx on mind.utm_sessoes (criado_em desc);
alter table mind.utm_sessoes enable row level security;

comment on table mind.utm_sessoes is
  'Ponte de atribuição site -> WhatsApp. O site registra a UTM e recebe um token curto, que viaja no texto pré-preenchido do wa.me.';

alter table treble.conversations
  add column if not exists utm jsonb,
  add column if not exists utm_token text;

-- Chamada pelo site (anon). Só escreve: nunca lê nem devolve dado de ninguém.
-- gen_random_bytes vive em pgcrypto (schema extensions, fora do search_path
-- desta função); gen_random_uuid é core do Postgres e resolve.
create or replace function public.mind_utm_registrar(p_dados jsonb)
returns text
language plpgsql security definer set search_path = public, mind
as $fn$
declare
  t text;
  tentativa int := 0;
begin
  loop
    t := substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);
    exit when not exists (select 1 from mind.utm_sessoes where token = t);
    tentativa := tentativa + 1;
    if tentativa > 20 then raise exception 'nao foi possivel gerar token'; end if;
  end loop;

  insert into mind.utm_sessoes (
    token, site, origem_codigo, utm_source, utm_medium, utm_campaign,
    utm_content, utm_term, gclid, fbclid, referrer, landing_url)
  values (
    t,
    left(nullif(trim(p_dados->>'site'),''), 40),
    (select o.codigo from mind.origens o
      where o.codigo = nullif(trim(p_dados->>'origem'),'') and o.ativo),
    left(nullif(trim(p_dados->>'utm_source'),''), 120),
    left(nullif(trim(p_dados->>'utm_medium'),''), 120),
    left(nullif(trim(p_dados->>'utm_campaign'),''), 200),
    left(nullif(trim(p_dados->>'utm_content'),''), 200),
    left(nullif(trim(p_dados->>'utm_term'),''), 200),
    left(nullif(trim(p_dados->>'gclid'),''), 200),
    left(nullif(trim(p_dados->>'fbclid'),''), 200),
    left(nullif(trim(p_dados->>'referrer'),''), 500),
    left(nullif(trim(p_dados->>'landing_url'),''), 500));

  return t;
end;
$fn$;
grant execute on function public.mind_utm_registrar(jsonb) to anon, authenticated;

-- Postgres não tem urlencode nativo. Sem isto, "utm_term=evento bem estar
-- corporativo" sai com espaços literais e quebra o link no WhatsApp.
create or replace function public.mind_urlencode(p text)
returns text language sql immutable
as $fn$
  select coalesce(string_agg(
    case when c ~ '^[A-Za-z0-9_.~-]$' then c
         else (select string_agg('%' || upper(substring(x.h from i for 2)), '')
                 from (select encode(convert_to(c, 'UTF8'), 'hex') as h) x,
                      generate_series(1, length(x.h), 2) as i)
    end, '' order by n), '')
  from unnest(string_to_array(p, null)) with ordinality as u(c, n);
$fn$;

create or replace function public.mind_checkout_url(
  p_url text, p_utm jsonb default null,
  p_origem text default null, p_conversa text default null
) returns text
language sql stable security definer set search_path = public, mind
as $fn$
  select p_url
      || case when position('?' in p_url) > 0 then '&' else '?' end
      || 'utm_source='   || public.mind_urlencode(coalesce(nullif(p_utm->>'utm_source',''),
                              (select o.site from mind.origens o where o.codigo = p_origem), 'mind'))
      || '&utm_medium='  || public.mind_urlencode(coalesce(nullif(p_utm->>'utm_medium',''), 'chatbot'))
      || '&utm_campaign='|| public.mind_urlencode(coalesce(nullif(p_utm->>'utm_campaign',''), 'mind-summit-2026'))
      || '&utm_content=' || public.mind_urlencode(coalesce(nullif(p_utm->>'utm_content',''),
                              nullif(p_origem,''), 'sem_origem'))
      || case when nullif(p_utm->>'utm_term','') is null then ''
              else '&utm_term=' || public.mind_urlencode(p_utm->>'utm_term') end
      -- Sem gclid/fbclid o Google e a Meta não fecham a conversão com o
      -- clique que a gerou.
      || case when nullif(p_utm->>'gclid','') is null then ''
              else '&gclid=' || public.mind_urlencode(p_utm->>'gclid') end
      || case when nullif(p_utm->>'fbclid','') is null then ''
              else '&fbclid=' || public.mind_urlencode(p_utm->>'fbclid') end
      || '&mind_canal=chatbot'
      || case when nullif(p_origem,'') is null then ''
              else '&mind_origem=' || public.mind_urlencode(p_origem) end
      || case when nullif(p_conversa,'') is null then ''
              else '&mind_conversa=' || public.mind_urlencode(p_conversa) end;
$fn$;
revoke all on function public.mind_checkout_url(text, jsonb, text, text)
  from public, anon, authenticated;

create or replace function public.mind_material_link(
  p_url text, p_codigo text, p_utm_campaign text, p_canal text, p_origem text default null
) returns text
language sql stable security definer set search_path = public, mind
as $fn$
  select p_url
      || case when position('?' in p_url) > 0 then '&' else '?' end
      || 'utm_source=' || public.mind_urlencode(coalesce(
           (select o.site from mind.origens o where o.codigo = p_origem), 'mind'))
      || '&utm_medium=' || case p_canal
            when 'whatsapp_treble' then 'chatbot'
            when 'site_concierge'  then 'chatbot_concierge'
            else public.mind_urlencode(p_canal) end
      || '&utm_campaign=' || public.mind_urlencode(coalesce(nullif(p_utm_campaign,''), p_codigo))
      || '&utm_content=' || public.mind_urlencode(coalesce(nullif(p_origem,''), 'sem_origem'));
$fn$;
revoke all on function public.mind_material_link(text, text, text, text, text)
  from public, anon, authenticated;

-- start resolve o token; primeira gravação vence (a atribuição é da entrada).
drop function if exists public.treble_agent_start(text, jsonb, text);

create or replace function public.treble_agent_start(
  p_session_external_id text,
  p_contact jsonb default '{}'::jsonb,
  p_origem text default null,
  p_utm_token text default null
) returns jsonb
language plpgsql security definer set search_path = public, mind, treble
as $fn$
declare
  conv treble.conversations;
  hist jsonb;
  u mind.utm_sessoes;
  origem_final text;
begin
  if p_session_external_id is null or length(p_session_external_id) < 3 then
    raise exception 'session_external_id invalido';
  end if;

  select * into u from mind.utm_sessoes
   where token = nullif(trim(coalesce(p_utm_token,'')),'');

  -- A origem pode vir do payload do Treble ou de dentro da sessão de UTM.
  origem_final := coalesce(
    (select o.codigo from mind.origens o
      where o.codigo = nullif(trim(coalesce(p_origem,'')),'') and o.ativo),
    u.origem_codigo);

  insert into treble.conversations
    (session_external_id, nome_contato, telefone, telefone_hash, origem_codigo, utm_token, utm)
  values (
    p_session_external_id,
    nullif(trim(coalesce(p_contact->>'nome','')),''),
    nullif(trim(coalesce(p_contact->>'telefone','')),''),
    nullif(trim(coalesce(p_contact->>'telefone_hash','')),''),
    origem_final,
    u.token,
    case when u.token is null then null else jsonb_strip_nulls(jsonb_build_object(
      'utm_source', u.utm_source, 'utm_medium', u.utm_medium,
      'utm_campaign', u.utm_campaign, 'utm_content', u.utm_content,
      'utm_term', u.utm_term, 'gclid', u.gclid, 'fbclid', u.fbclid,
      'site', u.site, 'referrer', u.referrer, 'landing_url', u.landing_url)) end)
  on conflict (session_external_id) do update
    set ultima_atividade = now(),
        nome_contato = coalesce(treble.conversations.nome_contato, excluded.nome_contato),
        telefone = coalesce(treble.conversations.telefone, excluded.telefone),
        telefone_hash = coalesce(treble.conversations.telefone_hash, excluded.telefone_hash),
        origem_codigo = coalesce(treble.conversations.origem_codigo, excluded.origem_codigo),
        utm_token = coalesce(treble.conversations.utm_token, excluded.utm_token),
        utm = coalesce(treble.conversations.utm, excluded.utm)
  returning * into conv;

  if u.token is not null then
    update mind.utm_sessoes set usado_em = coalesce(usado_em, now()) where token = u.token;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('papel', m.papel, 'conteudo', m.conteudo)
                            order by m.criado_em), '[]'::jsonb)
    into hist
  from (select papel, conteudo, criado_em from treble.messages
         where conversation_id = conv.id order by criado_em desc limit 12) m;

  return jsonb_build_object(
    'conversation_id', conv.id, 'audience', conv.audience, 'stage', conv.stage,
    'variables', conv.variables, 'nome_contato', conv.nome_contato,
    'origem_codigo', conv.origem_codigo, 'utm', conv.utm, 'historico', hist);
end;
$fn$;
revoke all on function public.treble_agent_start(text, jsonb, text, text)
  from public, anon, authenticated;

-- O contexto entrega o checkout JÁ com a atribuição embutida: o agente só
-- copia o que está em checkout_url, nunca monta URL.
drop function if exists public.treble_agent_context(text, text);

create or replace function public.treble_agent_context(
  p_audience text default 'desconhecido',
  p_origem text default null,
  p_utm jsonb default null,
  p_conversa text default null
) returns jsonb
language sql security definer set search_path = public, mind, treble
as $fn$
select public.treble_agent_context_base()
  || jsonb_build_object(
    'ofertas_vigentes', (
      select coalesce(jsonb_agg(jsonb_build_object(
        'codigo', o.codigo, 'nome', o.nome, 'valor', o.valor,
        'condicoes_pagamento', o.condicoes_pagamento,
        'checkout_url', public.mind_checkout_url(o.checkout_url, p_utm, p_origem, p_conversa),
        'lote_termina_em', o.encerra_em,
        'procura', o.procura, 'procura_nota', o.procura_nota)), '[]'::jsonb)
      from mind.offers o where o.ativo and o.publico),
    'momento', public.treble_momento(),
    'origem_da_conversa', public.mind_origem(p_origem),
    'precos_por_volume', public.mind_precos_por_volume(),
    'materiais_que_posso_enviar', public.treble_materiais(p_audience, p_origem)
  )
$fn$;
revoke all on function public.treble_agent_context(text, text, jsonb, text)
  from public, anon, authenticated;
