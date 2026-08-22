-- Virada de lote como regra de escassez (Adriana, 2026-08-22):
-- "os lotes viram sempre na quinta; a gente começa a comunicar na quinta
-- anterior — faltam sete dias — e conta 6, 5, 4, 3, 2, 1."
--
-- Duas coisas viram código por causa disso:
-- 1. O agente não conta dias sozinho. Contar data é onde LLM erra e onde
--    o erro não é auditável. A conta sai do banco pronta, com os dias
--    restantes, se a janela está aberta e quanto cada categoria sobe.
--    A janela (7) é configurável em treble.config.janela_urgencia_dias.
-- 2. "Quando o lote vira, quem estava em dúvida corre e a categoria pode
--    não ficar mais disponível" só pode ser dito quando for verdade.
--    Vira campo controlado por oferta (procura), nunca dedução do modelo.
--    Autorizado por ela: VIP e Prime estão bastante vendidos.

insert into treble.config (chave, valor) values ('janela_urgencia_dias', '7')
on conflict (chave) do update set valor = excluded.valor;

alter table mind.offers
  add column if not exists procura text not null default 'normal'
    check (procura in ('normal','alta','ultimas_vagas')),
  add column if not exists procura_nota text;

comment on column mind.offers.procura is
  'Nível de procura desta categoria. O agente só pode citar escassez quando este campo disser que ela existe — nunca por dedução.';

update mind.offers
   set procura = 'alta',
       procura_nota = 'Categoria com bastante venda. Pode dizer que tem alta procura e que, na virada de lote, quem estava em dúvida corre — sem prometer que vai esgotar em data nenhuma.',
       atualizado_em = now()
 where elegibilidade->>'categoria' in ('vip','prime');

-- TMDay depende do locale do servidor (voltou "Thursday"): dia da semana
-- em português sem depender de lc_time.
create or replace function public.mind_virada_de_lote()
returns jsonb
language sql security definer set search_path = public, mind, treble
as $fn$
  with janela as (
    select coalesce((select valor::int from treble.config where chave = 'janela_urgencia_dias'), 7) as dias
  ), atual as (
    select o.elegibilidade->>'categoria' as categoria, o.valor, o.encerra_em
    from mind.offers o
    where o.ativo and o.publico and o.encerra_em is not null
      and not (o.elegibilidade ? 'grupo')
  ), fim as (
    select min(encerra_em) as encerra_em from atual
  ), proximo as (
    select o.elegibilidade->>'categoria' as categoria, o.valor
    from mind.offers o
    where not o.ativo and o.inicia_em is not null and o.inicia_em > now()
      and not (o.elegibilidade ? 'grupo')
      and o.inicia_em = (select min(i.inicia_em) from mind.offers i
                          where i.inicia_em > now() and not (i.elegibilidade ? 'grupo'))
  ), conta as (
    select f.encerra_em,
           (f.encerra_em at time zone 'America/Sao_Paulo') as fim_sp,
           ((f.encerra_em at time zone 'America/Sao_Paulo')::date
            - (now() at time zone 'America/Sao_Paulo')::date) as dias_restantes,
           j.dias as janela_dias
    from fim f cross join janela j
  )
  select case when (select encerra_em from conta) is null then null else
    jsonb_build_object(
      'ultimo_dia_do_lote_atual', to_char((select fim_sp from conta), 'DD/MM/YYYY'),
      'dia_da_semana', (select case extract(isodow from fim_sp)
          when 1 then 'segunda-feira' when 2 then 'terca-feira' when 3 then 'quarta-feira'
          when 4 then 'quinta-feira'  when 5 then 'sexta-feira' when 6 then 'sabado'
          else 'domingo' end from conta),
      'dias_restantes', (select dias_restantes from conta),
      'janela_de_comunicacao_dias', (select janela_dias from conta),
      'pode_usar_como_urgencia',
        (select dias_restantes <= janela_dias and dias_restantes >= 0 from conta),
      'como_falar', case
        when (select dias_restantes from conta) < 0 then 'Lote ja virou: nao mencione contagem.'
        when (select dias_restantes from conta) > (select janela_dias from conta)
          then 'Ainda falta muito para a virada. NAO use a virada de lote como urgencia nesta conversa; venda pelo conteudo.'
        when (select dias_restantes from conta) = 0
          then 'Hoje e o ultimo dia deste lote. Diga isso com clareza, uma vez, sem pressionar.'
        when (select dias_restantes from conta) = 1
          then 'Falta 1 dia para a virada. Pode dizer.'
        else 'Faltam ' || (select dias_restantes from conta) || ' dias para a virada. Pode dizer.' end,
      'aumentos', (
        select coalesce(jsonb_agg(jsonb_build_object(
                 'categoria', a.categoria, 'valor_hoje', a.valor,
                 'valor_depois_da_virada', p.valor,
                 'aumento', p.valor - a.valor) order by a.valor), '[]'::jsonb)
        from atual a join proximo p on p.categoria = a.categoria
        where p.valor > a.valor)
    ) end;
$fn$;
revoke all on function public.mind_virada_de_lote() from public, anon, authenticated;

-- A virada e a procura entram no contexto oficial; 'procura' viaja junto de
-- cada oferta para o agente nunca deduzir escassez de lugar nenhum.
-- (treble_agent_context_base recriada com os dois blocos novos — ver
--  20260822_utm_sessoes_e_checkout.sql para a versão do wrapper.)
create or replace function public.treble_agent_context_base()
returns jsonb
language sql security definer set search_path = public, mind, treble
as $fn$
select jsonb_build_object(
  'evento', (select to_jsonb(e) - 'id' from mind.events e limit 1),
  'experiencias_o_que_inclui', (
    select coalesce(jsonb_agg(jsonb_build_object('titulo', k.titulo, 'texto', left(k.corpo, 1500))), '[]'::jsonb)
    from mind.knowledge_documents k where k.tipo_conteudo = 'ingresso' and k.aprovado_treble),
  'faq', (
    select coalesce(jsonb_agg(jsonb_build_object('titulo', k.titulo, 'texto', left(k.corpo, 1200))), '[]'::jsonb)
    from mind.knowledge_documents k where k.tipo_conteudo = 'faq' and k.aprovado_treble),
  'conteudo_aprovado', (
    select coalesce(jsonb_agg(jsonb_build_object('titulo', k.titulo, 'texto', left(k.corpo, 1200))), '[]'::jsonb)
    from mind.knowledge_documents k
    where k.tipo_conteudo not in ('ingresso','faq') and k.aprovado_treble),
  'visao_geral', case when (select valor from treble.config where chave='bloco_visao_geral') = 'true'
    then jsonb_build_object(
      'numeros', jsonb_build_object(
        'sessoes', (select count(*) from mind.sessions),
        'palestrantes', (select count(*) from mind.speakers), 'dias', 2),
      'trilhas', (select coalesce(jsonb_agg(distinct t.trilha), '[]'::jsonb)
                  from mind.sessions s, unnest(s.trilhas) as t(trilha)),
      'palestrantes_destaque', (
        select coalesce(jsonb_agg(jsonb_build_object(
          'nome', d.nome, 'cargo', d.cargo, 'organizacao', d.organizacao)), '[]'::jsonb)
        from (select nome, cargo, organizacao from mind.speakers where destaque order by nome limit 12) d),
      'publico_e_dores', (
        select coalesce(jsonb_agg(x.rotulo), '[]'::jsonb)
        from (select rotulo from mind.taxonomy where ativo and tipo in ('area','dor') limit 18) x))
    else '"bloco desligado"'::jsonb end,
  'ofertas_vigentes', (
    select coalesce(jsonb_agg(jsonb_build_object(
      'codigo', o.codigo, 'nome', o.nome, 'valor', o.valor,
      'condicoes_pagamento', o.condicoes_pagamento, 'checkout_url', o.checkout_url,
      'lote_termina_em', o.encerra_em,
      'procura', o.procura, 'procura_nota', o.procura_nota)), '[]'::jsonb)
    from mind.offers o where o.ativo and o.publico),
  'virada_de_lote', public.mind_virada_de_lote(),
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
  'politicas', case when (select valor from treble.config where chave='bloco_politicas') = 'true'
    then (select coalesce(jsonb_agg(jsonb_build_object('titulo', p.titulo, 'texto', p.texto)), '[]'::jsonb)
          from mind.policies p where p.ativo)
    else '"bloco desligado"'::jsonb end
)
$fn$;
revoke all on function public.treble_agent_context_base() from public, anon, authenticated;

update treble.prompts set
  conteudo = conteudo || E'\n\n' ||
'VIRADA DE LOTE — a urgência tem janela, e ela é definida pelos dados, não por você. O bloco virada_de_lote traz dias_restantes, pode_usar_como_urgencia e uma instrução em como_falar. Obedeça:
- pode_usar_como_urgencia = false: NÃO mencione virada, contagem de dias nem aumento de preço. Venda pelo conteúdo. Falar de prazo longe demais soa a pressão inventada.
- pode_usar_como_urgencia = true: pode dizer quantos dias faltam e qual o dia da semana em que o lote vira, uma vez, sem repetir a cada mensagem. O quanto o preço sobe está em aumentos — use o número de lá, nunca calcule.
- Nunca conte dias por conta própria a partir de datas. Use dias_restantes como está.

PROCURA — só existe escassez de categoria quando o campo procura da oferta disser. Se procura = "alta" ou "ultimas_vagas", você pode dizer que a categoria tem bastante procura e que, na virada, quem estava em dúvida corre e a categoria pode não seguir disponível. Se procura = "normal", não insinue nada disso. Nunca prometa que vai esgotar em data nenhuma, e nunca invente número de vagas.',
  versao = versao + 1, atualizado_em = now()
where chave = 'base';
