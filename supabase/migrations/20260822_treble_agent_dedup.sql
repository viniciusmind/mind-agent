-- Deduplicação de turnos: o Treble dispara o webhook mais de uma vez para
-- a mesma fala do lead (observado no teste real de 2026-08-22: cada
-- mensagem chegou 2x em ~2s). Sem isso o bot responde em dobro, repete
-- perguntas e paga duas chamadas de LLM. Se a mesma fala já foi
-- respondida há poucos segundos, devolvemos a resposta anterior.
create or replace function public.treble_agent_resposta_repetida(
  p_conversation_id uuid,
  p_mensagem text,
  p_janela_segundos integer default 90
) returns text
language sql security definer set search_path = public, treble
as $$
  select a.conteudo
    from treble.messages l
    join lateral (
      select m.conteudo
        from treble.messages m
       where m.conversation_id = l.conversation_id
         and m.papel = 'agente'
         and m.criado_em >= l.criado_em
       order by m.criado_em
       limit 1
    ) a on true
   where l.conversation_id = p_conversation_id
     and l.papel = 'lead'
     and l.conteudo = p_mensagem
     and l.criado_em > now() - make_interval(secs => p_janela_segundos)
   order by l.criado_em desc
   limit 1;
$$;

comment on function public.treble_agent_resposta_repetida(uuid, text, integer) is
  'Devolve a resposta já dada para a mesma fala do lead dentro da janela (deduplicação de webhook duplicado do Treble).';

revoke all on function public.treble_agent_resposta_repetida(uuid, text, integer) from public, anon, authenticated;
