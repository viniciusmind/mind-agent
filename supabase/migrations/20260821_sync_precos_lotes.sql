-- Sincronização contínua de preços/lotes: fonte da verdade
-- (mind-summit-propostas, via Edge Function pública `pricing`) → mind.offers.
-- Aplicada em 2026-08-21 no projeto ymnmotgglsrxmjmonwjz (migration
-- "sync_precos_lotes"). A Edge Function mindagent-sync-precos busca o
-- payload e chama esta RPC; o pg_cron dispara a função a cada 30 min.

create extension if not exists pg_cron;
create extension if not exists pg_net;

create or replace function public.mindagent_sync_offers(
  p_vigente integer,
  p_lotes jsonb,
  p_tiers jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public, mind
as $$
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

  -- D-13: ofertas de grupo (valor fixo) ficam sempre desativadas —
  -- desconto de grupo é pelos tiers percentuais (commercial_rules).
  update mind.offers
     set ativo = false, publico = false, atualizado_em = now()
   where event_id = ev and elegibilidade ? 'grupo' and (ativo or publico);

  -- Tiers de desconto por volume
  update mind.commercial_rules
     set config = jsonb_build_object('tiers', p_tiers, 'acao', 'handoff_vendedor'),
         atualizado_em = now()
   where chave = 'desconto_por_volume';

  return jsonb_build_object('vigente', p_vigente, 'ofertas_sincronizadas', n_upserts);
end;
$$;

comment on function public.mindagent_sync_offers(integer, jsonb, jsonb) is
  'Upsert de mind.offers a partir do payload da fonte de preços (mind-summit-propostas). Chamada só pela Edge Function mindagent-sync-precos (service role).';

revoke all on function public.mindagent_sync_offers(integer, jsonb, jsonb) from public, anon, authenticated;

-- Dispara a sincronização a cada 30 minutos (job nomeado: re-agendar substitui)
select cron.schedule(
  'mindagent-sync-precos',
  '*/30 * * * *',
  $cron$ select net.http_post(
    url := 'https://ymnmotgglsrxmjmonwjz.supabase.co/functions/v1/mindagent-sync-precos',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := '{}'::jsonb
  ) $cron$
);
