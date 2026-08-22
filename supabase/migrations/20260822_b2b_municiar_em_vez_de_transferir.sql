-- Item 10 aprovado pela Adriana: em B2B o gargalo não é a transferência,
-- é a munição. Quem diz "preciso da aprovação do diretor" não quer um
-- vendedor: quer argumento para defender a compra lá dentro.
--
-- Três lugares mandavam transferir cedo e precisavam mudar juntos —
-- o playbook, a regra comercial, e a sync de preços, que reescrevia a
-- regra a cada 30 minutos e desfazia a mudança sozinha.
-- Aplicada em 2026-08-22.

update treble.prompts set
  conteudo = replace(conteudo,
    'MODO CORPORATIVO. Aqui você qualifica e entrega para o time comercial — não fecha sozinho.',
    'MODO CORPORATIVO. Seu trabalho aqui é armar a pessoa para comprar e para defender a compra dentro da empresa — não é despachar para o comercial. Você informa condição de grupo, monta a conta e entrega argumento; o consultor entra quando a negociação exigir.'),
  versao = versao + 1,
  atualizado_em = now()
where chave = 'playbook_b2b';

update treble.prompts set
  conteudo = replace(conteudo,
    'Assim que tiver empresa e quantidade (ou se a pessoa pedir), acione needs_human=true, avise que um consultor assume, e resuma o que já entendeu.',
    'Não transfira só porque já sabe empresa e quantidade — esse é o erro que mais perde lead B2B. Acione needs_human=true quando a pessoa pedir, ou quando a negociação exigir de fato (contrato, nota fiscal, condição fora da regra): aí avise que um consultor assume e resuma o que já entendeu.'),
  versao = versao + 1,
  atualizado_em = now()
where chave = 'playbook_b2b';

update mind.commercial_rules set
  descricao = 'Descontos por volume de ingressos (fonte: pricing_tiers do mind-summit-propostas). O agente informa o percentual do tier na primeira resposta sobre grupo e ajuda a montar a conta; handoff só por necessidade.',
  config = config || jsonb_build_object(
    'acao', 'informar_tier_e_municiar',
    'nota', 'Diga o percentual do tier que corresponde à quantidade, some com preço e parcelamento, e pergunte quantas pessoas. Transferir só se a pessoa pedir ou a negociação exigir (contrato, nota fiscal, condição fora da regra).'),
  atualizado_em = now()
where chave = 'desconto_por_volume';

-- A sync escrevia jsonb_build_object('tiers', ..., 'acao', 'handoff_vendedor'),
-- apagando a política a cada execução. Agora ela só toca nos tiers.
create or replace function public.mindagent_sync_offers(
  p_vigente integer,
  p_lotes jsonb,
  p_tiers jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public, mind
as $fn$
declare
  ev uuid;
  n_upserts integer := 0;
begin
  select id into ev from mind.events limit 1;
  if ev is null then
    raise exception 'nenhum evento cadastrado em mind.events';
  end if;

  with lotes as (
    select (l->>'numero')::int as numero,
           nullif(l->>'inicio','')::timestamptz as inicio,
           nullif(l->>'fim','')::timestamptz as fim,
           l->'precos' as precos
    from jsonb_array_elements(p_lotes) l
  ), linhas as (
    select lo.numero, lo.inicio, lo.fim, s.slug, (lo.precos->>s.slug)::numeric as preco
    from lotes lo
    cross join (values ('mind'),('vip'),('prime')) as s(slug)
    where lo.precos ? s.slug
  ), ins as (
    insert into mind.offers as o
      (event_id, codigo, nome, descricao, moeda, valor, condicoes_pagamento,
       checkout_url, elegibilidade, publico, ativo, inicia_em, encerra_em)
    select ev,
      li.slug || '-lote-' || li.numero,
      case li.slug when 'mind' then 'Experiência Mind'
                   when 'vip' then 'Experiência VIP'
                   else 'Experiência Prime' end || ' — Lote ' || li.numero,
      case when li.numero = p_vigente then 'Lote vigente' end,
      'BRL', li.preco,
      '12x de R$ ' || round(li.preco / 12),
      case li.slug when 'mind' then 'https://sun.eduzz.com/89AQDKYGWD'
                   when 'vip' then 'https://sun.eduzz.com/40Q3EKPK0B'
                   else 'https://sun.eduzz.com/E05XKB2KWX' end,
      jsonb_build_object('categoria', li.slug, 'lote', li.numero,
                         'fonte', 'mind-summit-propostas'),
      li.numero = p_vigente,
      li.numero = p_vigente,
      li.inicio, li.fim
    from linhas li
    on conflict (event_id, codigo) do update set
      valor = excluded.valor,
      condicoes_pagamento = excluded.condicoes_pagamento,
      checkout_url = excluded.checkout_url,
      descricao = excluded.descricao,
      elegibilidade = o.elegibilidade || excluded.elegibilidade,
      publico = excluded.publico,
      ativo = excluded.ativo,
      inicia_em = excluded.inicia_em,
      encerra_em = excluded.encerra_em,
      atualizado_em = now()
    returning 1
  ) select count(*) into n_upserts from ins;

  -- D-13: ofertas de grupo com valor fixo ficam sempre desativadas.
  update mind.offers
     set ativo = false, publico = false, atualizado_em = now()
   where event_id = ev and elegibilidade ? 'grupo' and (ativo or publico);

  -- Só os tiers vêm da fonte de preços. 'acao' e 'nota' são política
  -- comercial (item 10) e ficam preservados entre sincronizações.
  update mind.commercial_rules
     set config = config || jsonb_build_object('tiers', p_tiers),
         atualizado_em = now()
   where chave = 'desconto_por_volume';

  return jsonb_build_object('vigente', p_vigente, 'ofertas_sincronizadas', n_upserts);
end;
$fn$;

revoke all on function public.mindagent_sync_offers(integer, jsonb, jsonb) from public, anon, authenticated;
