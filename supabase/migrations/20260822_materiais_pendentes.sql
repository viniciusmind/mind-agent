-- "Coloca na lista de materiais o nome de cada um e deixa o resto em branco,
-- pelo menos a gente vai lembrar que tem que preencher." (Adriana)
--
-- Entram desligados e marcados como pendentes: material sem link não pode
-- ser oferecido, e o agente só enxerga o que está pronto.

alter table mind.materiais
  alter column url drop not null,
  alter column quando_usar drop not null;

alter table mind.materiais
  add column if not exists status text not null default 'pronto'
    check (status in ('pronto','pendente'));

comment on column mind.materiais.status is
  'pendente = cadastrado só com o nome, aguardando link/transcrição/ICP. Nunca fica ativo enquanto estiver pendente.';

insert into mind.materiais
  (codigo, titulo, tipo, url, quando_usar, descricao, status, ativo, audiencias, ordem)
values
('tour_3d', 'Tour 3D do evento', 'video', null, null,
 'Mostra como o evento foi redesenhado. Quebra desconfiança de quem teve experiência ruim na edição passada.',
 'pendente', false, array['b2c','b2b','desconhecido'], 10),
('video_evento_curto', 'Vídeo curto sobre o evento', 'video', null, null,
 'Usado no encerramento de conversa: fica no lugar do {video_evento} das mensagens de origem.',
 'pendente', false, array['b2c','b2b','desconhecido'], 20),
('video_descadastro', 'Vídeo rápido — mensagem de descadastro', 'video',
 'https://youtube.com/shorts/F283ezhqfJY', null,
 'Já tem link. Vai na mensagem de descadastro, sem tentar reverter.',
 'pendente', false, array['b2c','b2b','desconhecido'], 30),
('apresentacao_b2b', 'Apresentação B2B (PDF)', 'pdf', null, null,
 'Munição para quem precisa da aprovação do diretor: manda antes de a pessoa sumir.',
 'pendente', false, array['b2b'], 40),
('pdf_delegacoes', 'PDF de ingressos para delegações', 'pdf', null, null,
 'É o mesmo material que a pessoa baixa no site pelo botão delegacoes_pdf.',
 'pendente', false, array['b2b'], 50),
('pdf_programacao', 'PDF da programação', 'pdf', null, null,
 'Mesmo material do botão programacao_pdf do site.',
 'pendente', false, array['b2c','b2b','ja_comprou','desconhecido'], 60),
('site_b2b', 'Site mindsummit.company (oferta B2B)', 'pagina', null, null,
 'Onde a oferta B2B está desenhada. Precisa entrar na base de conhecimento também, não só como link.',
 'pendente', false, array['b2b'], 70),
('calculadora_grupo', 'Calculadora de desconto por grupo', 'pagina', null, null,
 'Existe, mas mandar para o lead brincar sozinho é too much (Adriana). O bot monta a conta; a calculadora é para o time.',
 'pendente', false, array['b2b'], 80),
('depoimentos', 'Depoimentos em vídeo', 'depoimento', null, null,
 'Precisa de um registro POR depoimento, com transcrição, ICP que atende e as dores que ele nomeia — sem isso não dá para escolher o certo para cada lead.',
 'pendente', false, array['b2c','b2b','desconhecido'], 90),
('videos_baixa_definicao', 'Pasta de vídeos em baixa definição (Drive)', 'outro', null, null,
 'Acervo bruto no Drive. Link de pasta do Drive não serve para mandar à lead: precisa do vídeo final publicado.',
 'pendente', false, array['b2c','b2b','desconhecido'], 100)
on conflict (codigo) do update set
  titulo = excluded.titulo, descricao = excluded.descricao,
  status = excluded.status, atualizado_em = now();

-- Guarda-corpo: material pendente nunca chega ao agente.
create or replace function public.mind_materiais_para(
  p_canal text default 'whatsapp_treble',
  p_audiencia text default 'desconhecido',
  p_icp text default null,
  p_origem text default null
) returns jsonb
language sql security definer set search_path = public, mind
as $fn$
  select coalesce(jsonb_agg(jsonb_build_object(
           'titulo', m.titulo, 'tipo', m.tipo,
           'sobre_o_que_e', m.conteudo_resumo,
           'quando_usar', m.quando_usar,
           'objecoes_que_quebra', m.objecoes_que_quebra,
           'link', public.mind_material_link(m.url, m.codigo, m.utm_campaign, p_canal, p_origem)
         ) order by m.ordem), '[]'::jsonb)
  from mind.materiais m
  where m.ativo and m.status = 'pronto' and m.url is not null
    and (coalesce(p_audiencia,'desconhecido') = any(m.audiencias))
    and (cardinality(m.icp) = 0 or p_icp is null or p_icp = any(m.icp));
$fn$;
revoke all on function public.mind_materiais_para(text, text, text, text)
  from public, anon, authenticated;
