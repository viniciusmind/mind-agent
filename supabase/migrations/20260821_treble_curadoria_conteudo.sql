-- Mecanismo de curadoria de conteúdo do bot (criado a pedido da Adriana,
-- e em seguida DESATIVADO por decisão dela na mesma noite: nada apagado,
-- nada desligado — todo conteúdo segue ativo; o mecanismo fica dormente
-- para uso futuro).
--   · mind.knowledge_documents.aprovado_treble (hoje: tudo true)
--   · flags de bloco em treble.config: bloco_visao_geral, bloco_politicas,
--     bloco_agenda_busca (hoje: todas 'true')
-- O corpo vigente de public.treble_agent_context (com os gates) está no
-- banco; ver também migration treble_agent_contexto_visao_geral.
alter table mind.knowledge_documents
  add column if not exists aprovado_treble boolean not null default false;
update mind.knowledge_documents set aprovado_treble = true;
insert into treble.config (chave, valor) values
  ('bloco_visao_geral', 'true'),
  ('bloco_politicas', 'true'),
  ('bloco_agenda_busca', 'true')
on conflict (chave) do update set valor = excluded.valor, atualizado_em = now();
