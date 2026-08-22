-- Modelo e timeout do agente viram configuração no banco: trocar de
-- modelo passa a ser um UPDATE em treble.config, sem redeploy.
-- Aplicada em 2026-08-21 (migration "treble_agent_config_modelo").
insert into treble.config (chave, valor) values
  ('openai_model', 'gpt-5.4'),
  ('timeout_ms', '20000')
on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();

create or replace function public.treble_agent_config() returns jsonb
language sql security definer set search_path = public, treble
as $$ select coalesce(jsonb_object_agg(chave, valor), '{}'::jsonb) from treble.config $$;
revoke all on function public.treble_agent_config() from public, anon, authenticated;
