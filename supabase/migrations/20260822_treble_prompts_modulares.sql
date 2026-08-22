-- Prompt do agente sai do código e vira conteúdo editável no banco.
-- Um cérebro só, com módulos compostos por turno:
--   base + tom_de_voz + playbook_<audiencia> [+ objecoes nas vendas]
-- Editar aqui vale na mensagem seguinte, sem deploy.
-- Aplicada em 2026-08-22 (migration "treble_prompts_modulares").
-- Os textos-semente de cada módulo estão no banco; ver treble.prompts.
create table treble.prompts (
  chave text primary key,
  titulo text not null,
  conteudo text not null,
  ativo boolean not null default true,
  versao integer not null default 1,
  atualizado_em timestamptz not null default now()
);
alter table treble.prompts enable row level security;

comment on table treble.prompts is
  'Prompt do agente em módulos. base e tom_de_voz entram sempre; playbook_<audiencia> entra conforme o roteador; objecoes entra nas conversas de venda. Editar aqui muda o comportamento na próxima mensagem.';

create or replace function public.treble_agent_prompt(p_audience text default 'desconhecido')
returns text
language sql security definer set search_path = public, treble
as $$
  select string_agg(conteudo, E'\n\n' order by ordem)
  from (
    select conteudo, 1 as ordem from treble.prompts where chave = 'base' and ativo
    union all
    select conteudo, 2 from treble.prompts where chave = 'tom_de_voz' and ativo
    union all
    select conteudo, 3 from treble.prompts
     where chave = 'playbook_' || coalesce(nullif(p_audience,''), 'desconhecido') and ativo
    union all
    select conteudo, 4 from treble.prompts
     where chave = 'objecoes' and ativo
       and coalesce(p_audience,'desconhecido') in ('b2c','desconhecido','b2b')
  ) partes;
$$;
revoke all on function public.treble_agent_prompt(text) from public, anon, authenticated;
