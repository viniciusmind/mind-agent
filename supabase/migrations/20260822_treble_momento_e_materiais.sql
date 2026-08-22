-- 1) Expediente NÃO é regra dura (correção da Adriana): vendedores atendem
--    à noite e no fim de semana. O que decide o handoff é a NECESSIDADE.
--    treble_momento() é só sinal de contexto para calibrar expectativa.
-- 2) mind.materiais: vídeos, depoimentos e páginas que o agente pode
--    oferecer — link em vez de arquivo (preview, leve, mensurável).
--    Especialmente útil quando o humano vai demorar: melhor um bom
--    material do que deixar a pessoa no vácuo.
-- 3) O contexto do agente passa a incluir momento + materiais.
-- Aplicada em 2026-08-22.

delete from treble.config where chave in ('expediente_dias','expediente_inicio','expediente_fim');
drop function if exists public.treble_expediente();

create or replace function public.treble_momento() returns jsonb
language sql security definer set search_path = public
as $$
  select jsonb_build_object(
    'agora', to_char(now() at time zone 'America/Sao_Paulo', 'TMDay, DD/MM HH24:MI'),
    'fim_de_semana', extract(isodow from now() at time zone 'America/Sao_Paulo') in (6,7),
    'fora_do_horario_comum', (
      extract(isodow from now() at time zone 'America/Sao_Paulo') in (6,7)
      or (now() at time zone 'America/Sao_Paulo')::time < '09:00'
      or (now() at time zone 'America/Sao_Paulo')::time >= '19:00'
    ),
    'nota', 'Sinal de contexto, não regra: o time às vezes atende à noite e no fim de semana. Transfira pela necessidade, nunca pelo horário. Se transferir em momento de resposta mais lenta, seja honesto sobre isso sem prometer prazo.'
  );
$$;
revoke all on function public.treble_momento() from public, anon, authenticated;

create table mind.materiais (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique,
  titulo text not null,
  descricao text,
  tipo text not null default 'video'
    check (tipo in ('video','depoimento','pagina','pdf','outro')),
  url text not null,
  quando_usar text not null,
  audiencias text[] not null default array['b2c','b2b','desconhecido'],
  ativo boolean not null default true,
  ordem integer not null default 100,
  atualizado_em timestamptz not null default now()
);
alter table mind.materiais enable row level security;

comment on table mind.materiais is
  'Vídeos, depoimentos e páginas que o agente pode oferecer na conversa. quando_usar descreve o momento certo; audiencias limita a quem cabe.';

create or replace function public.treble_materiais(p_audience text default 'desconhecido')
returns jsonb
language sql security definer set search_path = public, mind
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'titulo', m.titulo, 'tipo', m.tipo, 'url', m.url,
           'quando_usar', m.quando_usar) order by m.ordem), '[]'::jsonb)
  from mind.materiais m
  where m.ativo and (coalesce(p_audience,'desconhecido') = any(m.audiencias));
$$;
revoke all on function public.treble_materiais(text) from public, anon, authenticated;

-- treble_agent_context vira wrapper: corpo grande em _base + momento + materiais.
-- (corpo de treble_agent_context_base: ver definição vigente no banco)

-- ============================================================
-- Enriquecimento de mind.materiais (pedido da Adriana):
-- transcrição, resumo, objeções que quebra, ICP e UTM por canal.
-- A prateleira é compartilhada: o mesmo material rende links
-- diferentes no WhatsApp e no site, para medir separado.
-- ============================================================
alter table mind.materiais
  add column if not exists conteudo_resumo text,
  add column if not exists transcricao text,
  add column if not exists objecoes_que_quebra text[] default '{}',
  add column if not exists icp text[] default '{}',
  add column if not exists duracao_segundos integer,
  add column if not exists utm_campaign text;

create or replace function public.mind_material_link(
  p_url text, p_codigo text, p_utm_campaign text, p_canal text
) returns text
language sql immutable
as $$
  select p_url
      || case when position('?' in p_url) > 0 then '&' else '?' end
      || 'utm_source=' || case p_canal
            when 'whatsapp_treble' then 'whatsapp'
            when 'site_concierge'  then 'site'
            else 'mind' end
      || '&utm_medium=' || case p_canal
            when 'whatsapp_treble' then 'chatbot_whatsapp'
            when 'site_concierge'  then 'chatbot_site'
            else p_canal end
      || '&utm_campaign=' || coalesce(nullif(p_utm_campaign,''), p_codigo)
      || '&utm_content=agente';
$$;

create or replace function public.mind_materiais_para(
  p_canal text default 'whatsapp_treble',
  p_audiencia text default 'desconhecido',
  p_icp text default null
) returns jsonb
language sql security definer set search_path = public, mind
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
           'titulo', m.titulo, 'tipo', m.tipo,
           'sobre_o_que_e', m.conteudo_resumo,
           'quando_usar', m.quando_usar,
           'objecoes_que_quebra', m.objecoes_que_quebra,
           'link', public.mind_material_link(m.url, m.codigo, m.utm_campaign, p_canal)
         ) order by m.ordem), '[]'::jsonb)
  from mind.materiais m
  where m.ativo
    and (coalesce(p_audiencia,'desconhecido') = any(m.audiencias))
    and (cardinality(m.icp) = 0 or p_icp is null or p_icp = any(m.icp));
$$;
revoke all on function public.mind_materiais_para(text, text, text) from public, anon, authenticated;

create or replace function public.treble_materiais(p_audience text default 'desconhecido')
returns jsonb
language sql security definer set search_path = public, mind
as $$ select public.mind_materiais_para('whatsapp_treble', p_audience, null) $$;
