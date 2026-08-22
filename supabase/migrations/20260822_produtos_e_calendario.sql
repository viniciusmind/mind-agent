-- O Mind Summit 2026 é um PRODUTO, não o universo (Adriana, 2026-08-22):
-- "logo ele vai morrer e a gente vai começar a conversar sobre outros
-- produtos. Tem que já nascer pronto."
--
-- Se o produto não for coluna desde agora, o dia da virada vira refatoração
-- geral — e, pior, vira o agente vendendo evento que já aconteceu.
--
-- Duas peças:
-- 1. mind.produtos + produto_codigo em tudo que é conteúdo ou oferta.
--    NULL = vale para qualquer produto (tom de voz, política, LGPD).
-- 2. mind_calendario(): onde estamos no calendário DESTE produto. A conta
--    sai do banco, não do LLM. Depois do evento, venda vira atendimento.

create table if not exists mind.produtos (
  codigo text primary key,
  nome text not null,
  tipo text not null default 'evento'
    check (tipo in ('evento','formacao','assinatura','conteudo','outro')),
  linha text check (linha in ('summit','institute','dash','outro')),
  descricao_curta text,
  vende boolean not null default true,
  ativo boolean not null default true,
  comeca_em date,
  encerra_em date,
  atualizado_em timestamptz not null default now()
);

comment on table mind.produtos is
  'Cada coisa que o Mind vende ou sobre a qual os agentes conversam. vende=false: ainda responde, mas não vende. ativo=false: sai do contexto dos agentes.';
comment on column mind.produtos.linha is
  'Marca/família. Casa com mind.origens.site, que decide o utm_source.';

insert into mind.produtos (codigo, nome, tipo, linha, descricao_curta, comeca_em, encerra_em)
values ('mind-summit-2026', 'Mind Summit 2026', 'evento', 'summit',
        'Maior evento da América Latina sobre bem-estar no trabalho, liderança e alta performance. 16 e 17 de setembro de 2026, São Paulo Expo.',
        '2026-09-16', '2026-09-17')
on conflict (codigo) do nothing;

alter table mind.events add column if not exists produto_codigo text references mind.produtos(codigo);
update mind.events set produto_codigo = 'mind-summit-2026' where slug = 'mind-summit-2026';

alter table mind.knowledge_documents add column if not exists produto_codigo text references mind.produtos(codigo);
alter table mind.materiais           add column if not exists produto_codigo text references mind.produtos(codigo);
alter table mind.origens             add column if not exists produto_codigo text references mind.produtos(codigo);
alter table mind.commercial_rules    add column if not exists produto_codigo text references mind.produtos(codigo);
alter table mind.policies            add column if not exists produto_codigo text references mind.produtos(codigo);
alter table treble.prompts           add column if not exists produto_codigo text references mind.produtos(codigo);
alter table treble.conversations     add column if not exists produto_codigo text references mind.produtos(codigo);

comment on column mind.knowledge_documents.produto_codigo is
  'NULL = vale para qualquer produto. Preenchido = só entra no contexto quando o agente estiver falando desse produto.';

update mind.knowledge_documents set produto_codigo = 'mind-summit-2026'
 where produto_codigo is null and tipo_conteudo <> 'politica';
update mind.materiais         set produto_codigo = 'mind-summit-2026' where produto_codigo is null;
update mind.origens           set produto_codigo = 'mind-summit-2026' where produto_codigo is null;
update mind.commercial_rules  set produto_codigo = 'mind-summit-2026' where produto_codigo is null;
update treble.conversations   set produto_codigo = 'mind-summit-2026' where produto_codigo is null;
-- Políticas e tom de voz são da empresa, não do produto: ficam NULL de propósito.
-- Playbooks também: vender é vender; muda o que se vende.

insert into treble.config (chave, valor) values ('produto_padrao', 'mind-summit-2026')
on conflict (chave) do update set valor = excluded.valor;

create index if not exists knowledge_documents_produto_idx on mind.knowledge_documents (produto_codigo) where ativo;
create index if not exists materiais_produto_idx on mind.materiais (produto_codigo) where ativo;

-- --------------------------------------------------------------------
-- Calendário: que dia é hoje EM RELAÇÃO AO PRODUTO.
create or replace function public.mind_calendario(p_produto text default null)
returns jsonb
language sql stable security definer set search_path = public, mind, treble
as $fn$
  with alvo as (
    select p.* from mind.produtos p
    where p.codigo = coalesce(nullif(p_produto,''),
      (select valor from treble.config where chave = 'produto_padrao'))
  ), hoje as (
    select (now() at time zone 'America/Sao_Paulo')::date as d
  ), calc as (
    select a.codigo, a.nome, a.linha, a.vende, a.comeca_em, a.encerra_em, h.d as hoje,
           (a.comeca_em - h.d) as dias_ate_comecar,
           case
             when a.comeca_em is null then 'sem_data'
             when h.d > a.encerra_em then 'encerrado'
             when h.d >= a.comeca_em then 'acontecendo'
             when (a.comeca_em - h.d) <= 7 then 'semana_do_evento'
             else 'venda'
           end as fase
    from alvo a cross join hoje h
  )
  select case when (select count(*) from calc) = 0 then null else (
    select jsonb_build_object(
      'produto', c.codigo, 'nome', c.nome,
      'hoje', to_char(c.hoje, 'DD/MM/YYYY'),
      'comeca_em', to_char(c.comeca_em, 'DD/MM/YYYY'),
      'encerra_em', to_char(c.encerra_em, 'DD/MM/YYYY'),
      'dias_ate_comecar', c.dias_ate_comecar,
      'fase', c.fase,
      'pode_vender', c.vende and c.fase in ('venda','semana_do_evento','acontecendo'),
      'o_que_fazer', case c.fase
        when 'venda' then 'Faltam ' || c.dias_ate_comecar || ' dias para o evento. Modo venda normal.'
        when 'semana_do_evento' then 'E a semana do evento: faltam ' || c.dias_ate_comecar ||
             ' dias. Ainda vende, mas ja responda tambem duvidas de quem vai (credenciamento, local, horario).'
        when 'acontecendo' then 'O evento esta ACONTECENDO hoje. A prioridade e atendimento de quem esta la: credenciamento, salas, horarios. Venda so se a pessoa pedir.'
        when 'encerrado' then 'O evento JA ACONTECEU. NAO tente vender ingresso dele em hipotese nenhuma. Quem chega falando dele agora quer atendimento: certificado, gravacoes, nota fiscal, material. Se a pessoa quiser comprar, fale da proxima edicao se houver uma em proxima_edicao; se nao houver, diga com honestidade que as datas ainda nao foram anunciadas e ofereca avisar.'
        else 'Produto sem data cadastrada: nao afirme prazo nenhum.' end,
      'proxima_edicao', (
        select jsonb_build_object('codigo', p2.codigo, 'nome', p2.nome,
                                  'comeca_em', to_char(p2.comeca_em, 'DD/MM/YYYY'))
        from mind.produtos p2
        where p2.linha = c.linha and p2.ativo and p2.codigo <> c.codigo
          and p2.comeca_em > c.hoje
        order by p2.comeca_em limit 1))
    from calc c) end;
$fn$;
revoke all on function public.mind_calendario(text) from public, anon, authenticated;

comment on function public.mind_calendario(text) is
  'Onde estamos no calendário DESTE produto: fase, dias que faltam e o que o agente deve fazer. Depois do evento, venda vira atendimento.';

-- O contexto passa a receber o produto da conversa.
drop function if exists public.treble_agent_context(text, text, jsonb, text);

create or replace function public.treble_agent_context(
  p_audience text default 'desconhecido',
  p_origem text default null,
  p_utm jsonb default null,
  p_conversa text default null,
  p_produto text default null
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
    'calendario_do_produto', public.mind_calendario(p_produto),
    'momento', public.treble_momento(),
    'origem_da_conversa', public.mind_origem(p_origem),
    'precos_por_volume', public.mind_precos_por_volume(),
    'materiais_que_posso_enviar', public.treble_materiais(p_audience, p_origem)
  )
$fn$;
revoke all on function public.treble_agent_context(text, text, jsonb, text, text)
  from public, anon, authenticated;

update treble.prompts set
  conteudo = conteudo || E'\n\n' ||
'ONDE ESTAMOS NO CALENDARIO — o bloco calendario_do_produto diz que dia e hoje em relacao ao produto, em que fase estamos e o que fazer. Ele manda mais que qualquer instrucao de venda:
- fase "venda": normal, faltam os dias que o bloco informa.
- fase "semana_do_evento": ainda vende, mas ja responde duvida de quem vai (credenciamento, local, horario).
- fase "acontecendo": a prioridade e quem esta la agora. Venda so se pedirem.
- fase "encerrado": o evento JA ACONTECEU. Voce esta PROIBIDO de tentar vender ingresso dele. Quem chega falando dele agora quer atendimento — certificado, gravacoes, nota fiscal, material. Se a pessoa quiser comprar, fale da proxima edicao apenas se ela estiver em proxima_edicao; se nao estiver, diga com honestidade que as datas ainda nao foram anunciadas e ofereca avisar quando sairem.
Nunca calcule quantos dias faltam a partir de datas: use dias_ate_comecar como esta.',
  versao = versao + 1, atualizado_em = now()
where chave = 'base';
