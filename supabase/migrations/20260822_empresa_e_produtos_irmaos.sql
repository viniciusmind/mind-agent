-- "Info da empresa versus info de cada produto" (Adriana, 2026-08-22).
--
-- Até agora, conteúdo da empresa era representado por produto_codigo NULL —
-- implícito e invisível. Passa a existir um produto 'mind' com tipo
-- 'empresa': quem o Mind é, posicionamento, o que a empresa defende. NULL
-- fica reservado para o que é universal de verdade (tom de voz, LGPD).
--
-- Institute e Dash entram nomeados e DESLIGADOS, no mesmo padrão dos
-- materiais pendentes: existem para lembrarmos de preencher, e o agente não
-- fala deles enquanto ativo = false.

alter table mind.produtos drop constraint if exists produtos_tipo_check;
alter table mind.produtos add constraint produtos_tipo_check
  check (tipo in ('empresa','evento','formacao','assinatura','conteudo','outro'));

insert into mind.produtos (codigo, nome, tipo, linha, descricao_curta, vende, ativo)
values
  ('mind', 'Mind', 'empresa', null,
   'A empresa. Quem somos, posicionamento, o que defendemos sobre bem-estar no trabalho. Conteúdo institucional que vale para qualquer produto.',
   false, true),
  ('mind-institute', 'Mind Institute', 'formacao', 'institute',
   'PENDENTE: descrição, oferta e conteúdo ainda não cadastrados.', false, false),
  ('mind-dash', 'Mind Dash', 'outro', 'dash',
   'PENDENTE: descrição, oferta e conteúdo ainda não cadastrados.', false, false)
on conflict (codigo) do nothing;

comment on column mind.produtos.tipo is
  'empresa = o Mind em si, não um produto vendável. Os demais são produtos.';

-- Conteúdo que o agente pode usar falando de um produto: o do próprio
-- produto + o institucional da empresa + o universal (NULL). Nunca o de
-- outro produto — é isso que impede o bot do Summit de citar o Institute
-- sem querer.
create or replace function public.mind_conteudo(
  p_produto text default null,
  p_tipo text default null
) returns jsonb
language sql stable security definer set search_path = public, mind, treble
as $fn$
  with alvo as (
    select coalesce(nullif(p_produto,''),
                    (select valor from treble.config where chave = 'produto_padrao')) as codigo
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'titulo', k.titulo,
           'texto', left(k.corpo, 1500),
           'tipo', k.tipo_conteudo,
           'sobre', coalesce(k.produto_codigo, 'universal')) order by k.titulo), '[]'::jsonb)
  from mind.knowledge_documents k, alvo a
  where k.ativo
    and (k.produto_codigo is null
         or k.produto_codigo = a.codigo
         or k.produto_codigo = 'mind')
    and (p_tipo is null or k.tipo_conteudo = p_tipo);
$fn$;
revoke all on function public.mind_conteudo(text, text) from public, anon, authenticated;

comment on function public.mind_conteudo(text, text) is
  'Conteúdo visível para quem fala DESTE produto: o do produto + o institucional (produto mind) + o universal (NULL). Nunca o de outro produto.';
