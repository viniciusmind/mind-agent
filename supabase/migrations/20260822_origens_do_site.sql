-- Botões de entrada do site, do documento "Mensagens site summit 2"
-- (Adriana, 2026-08-22).
--
-- O documento previa "direcionar bot B2B", "bot roteador", "bot atendimento".
-- Com o cérebro único (D-1, D-11) isso deixa de ser roteamento entre bots:
-- vira audiencia_sugerida na origem, e a mesma conversa muda de postura sem
-- perder contexto. Um fluxo no Treble atende os cinco botões.
--
-- São dois campos ocultos por botão, então hubspot vira jsonb.
-- perfil_d_cliente ("Perfil do cliente") já existe no portal; a propriedade
-- de Intenção ainda precisa ser confirmada ou criada.

alter table mind.origens
  add column if not exists hubspot jsonb,
  add column if not exists mensagem_encerramento text,
  add column if not exists mensagem_descadastro text;

comment on column mind.origens.hubspot is
  'Campos ocultos do formulário do HubSpot para este botão: {propriedade: valor}.';

insert into mind.origens
  (codigo, site, botao_rotulo, descricao, audiencia_sugerida, hubspot,
   mensagem_abertura, mensagem_encerramento, mensagem_descadastro)
values
('delegacoes_condicoes_wpp', 'mindsummit',
 'Ingressos → Delegações → Ver condições no WhatsApp',
 'Quem já entende que quer levar equipe e pediu as condições de grupo. Entrada mais quente de B2B.',
 'b2b', '{"perfil_d_cliente": "B2B", "intencao": "Whatsapp"}'::jsonb,
 'Oi, {nome}! Tudo bem? Aqui é o assistente do Mind Summit.
Vi que você quer levar sua equipe ao Summit. Posso te ajudar a entender as condições para grupos e escolher os ingressos mais adequados para a sua equipe.
Por onde você quer começar?',
 null,
 'Tudo bem, você não vai mais receber mensagens sobre o Mind Summit. Se mudar de ideia ou quiser só dar uma olhada no evento, deixo aqui um vídeo rápido: https://youtube.com/shorts/F283ezhqfJY'),

('delegacoes_pdf', 'mindsummit',
 'Ingressos → Delegações → Baixar PDF',
 'Baixou o material de delegações. Intenção B2B declarada, mas ainda em pesquisa.',
 'b2b', '{"perfil_d_cliente": "B2B", "intencao": "Informações"}'::jsonb,
 'Oi, {nome}! Tudo bem? Aqui é o assistente do Mind Summit.
Vi que você baixou o material sobre ingressos para delegações. Posso te ajudar a entender melhor as opções de ingresso e as condições para levar sua equipe ao Summit.
Como posso te ajudar?',
 null,
 'Tudo bem, você não vai mais receber mensagens sobre o Mind Summit. Se mudar de ideia ou quiser só dar uma olhada no evento, deixo aqui um vídeo rápido: https://youtube.com/shorts/F283ezhqfJY'),

('programacao_pdf', 'mindsummit',
 'Programação → Baixar PDF',
 'Pediu a programação. Pode ser B2C, B2B ou quem já comprou — descobrir na conversa.',
 'desconhecido', '{"perfil_d_cliente": "Não sei", "intencao": "Informações"}'::jsonb,
 'Oi, {nome}, tudo bem? Aqui é o assistente do Mind Summit.
Vi que você pediu informações sobre o evento e queria saber se posso te ajudar com mais alguma coisa por aqui. Posso te ajudar com informações sobre o evento, ingressos ou dúvidas de quem já garantiu a participação.
O que você precisa agora?',
 'Tudo bem! Se quiser conhecer um pouco mais sobre o Mind Summit, deixo aqui um vídeo rápido sobre o evento: {video_evento}. Se surgir qualquer dúvida depois, é só me chamar por aqui.',
 'Tudo bem, você não vai mais receber mensagens sobre o Mind Summit. Se mudar de ideia ou quiser só dar uma olhada no evento, deixo aqui um vídeo rápido: https://youtube.com/shorts/F283ezhqfJY'),

('whatsapp_flutuante', 'mindsummit',
 'Botão flutuante de WhatsApp',
 'Entrada mais genérica do site. Modo descoberta.',
 'desconhecido', '{"perfil_d_cliente": "Não sei", "intencao": "Whatsapp"}'::jsonb,
 'Oi, {nome}! Tudo bem? Que bom ter você por aqui.
Sou o assistente do Mind Summit e posso te ajudar com informações sobre o evento, ingressos ou dúvidas de quem já garantiu a participação.
O que você precisa agora?',
 'Tudo bem! Se quiser conhecer um pouco mais sobre o Mind Summit, deixo aqui um vídeo rápido sobre o evento: {video_evento}. Se surgir qualquer dúvida depois, é só me chamar por aqui.',
 'Tudo bem, você não vai mais receber mensagens sobre o Mind Summit. Se mudar de ideia ou quiser só dar uma olhada no evento, deixo aqui um vídeo rápido: https://youtube.com/shorts/F283ezhqfJY'),

('whatsapp_popup', 'mindsummit',
 'Popup de WhatsApp',
 'Mesma mensagem do botão flutuante; muda só o campo oculto de intenção.',
 'desconhecido', '{"perfil_d_cliente": "Não sei", "intencao": "Informações"}'::jsonb,
 'Oi, {nome}! Tudo bem? Que bom ter você por aqui.
Sou o assistente do Mind Summit e posso te ajudar com informações sobre o evento, ingressos ou dúvidas de quem já garantiu a participação.
O que você precisa agora?',
 'Tudo bem! Se quiser conhecer um pouco mais sobre o Mind Summit, deixo aqui um vídeo rápido sobre o evento: {video_evento}. Se surgir qualquer dúvida depois, é só me chamar por aqui.',
 'Tudo bem, você não vai mais receber mensagens sobre o Mind Summit. Se mudar de ideia ou quiser só dar uma olhada no evento, deixo aqui um vídeo rápido: https://youtube.com/shorts/F283ezhqfJY')

on conflict (codigo) do update set
  site = excluded.site, botao_rotulo = excluded.botao_rotulo,
  descricao = excluded.descricao, audiencia_sugerida = excluded.audiencia_sugerida,
  hubspot = excluded.hubspot, mensagem_abertura = excluded.mensagem_abertura,
  mensagem_encerramento = excluded.mensagem_encerramento,
  mensagem_descadastro = excluded.mensagem_descadastro,
  atualizado_em = now();

create or replace function public.mind_origem(p_codigo text)
returns jsonb
language sql stable security definer set search_path = public, mind
as $fn$
  select case when p_codigo is null then null else (
    select jsonb_build_object(
      'codigo', o.codigo, 'site', o.site, 'botao', o.botao_rotulo,
      'descricao', o.descricao,
      'mensagem_abertura', o.mensagem_abertura,
      'mensagem_encerramento', o.mensagem_encerramento,
      'mensagem_descadastro', o.mensagem_descadastro,
      'hubspot', o.hubspot,
      'audiencia_sugerida', o.audiencia_sugerida)
    from mind.origens o where o.codigo = p_codigo and o.ativo
  ) end;
$fn$;
grant execute on function public.mind_origem(text) to anon, authenticated;
