# Registro de decisões

Formato: **D-n — decisão** · por quê · o que descarta. Decisões são
revisáveis, mas só com registro aqui.

---

**D-1 — O cérebro fica fora do Treble, numa Edge Function (`treble-inbound-agent`), plugada via webhook.**
Por quê: o agente nativo do Treble não reconsulta API a cada mensagem — o
teste de 2026-08-20 (`treble-find-location`) provou o limite. O Treble
suporta oficialmente "Integrate Your Own AI" via webhook de resposta +
`[REQUEST_TRIGGER]` + `POST /session/{id}/update`.
Descarta: agente nativo do Treble como cérebro; base de conhecimento
estática como fonte primária.

**D-2 — Tools são funções internas da Edge Function, não endpoints HTTP.**
Por quê: um endpoint por pergunta (modelo do teste de ontem e do plano
original: `get_ticket_info()` etc. como API) multiplica latência, custo e
pontos de falha, e deixa ao agente do Treble a decisão de quando chamar.
Dentro do processo, a consulta ao banco é direta e obrigatória.
Descarta: "Mind Intelligence API" como camada HTTP na V1 — ela volta no
backlog como camada pública quando outras superfícies (AI Coach, app)
precisarem da mesma inteligência.

**D-3 — Regras comerciais são código, não prompt.**
Por quê: "pode mencionar cupom?" não pode depender de obediência do LLM.
`get_commercial_rule()`/`check_coupon()` respondem determinística e
auditavelmente a partir de `commercial_rules`/`coupons`. Preço e checkout
só saem de tool call. Elimina por construção o erro P1 mais grave
(desconto indevido, preço inventado).

**D-4 — Sem máquina de estados rígida; estado é histórico + variáveis.**
Por quê: os 9 estados do plano original compensavam a falta de memória do
builder. Com o transcript em `conversations`, o LLM navega contexto melhor
que um grafo. Mantemos `stage` gravado por turno para métricas e follow-up,
não como trilho.
Descarta: fluxo ramificado extenso no Conversation Builder.

**D-5 — Mesmo repositório (`mind-agent`, pasta `treble/`) e mesmo projeto Supabase (`ymnmotgglsrxmjmonwjz`).**
Por quê: a fonte da verdade é uma só — agenda/palestrantes já vivem nesse
projeto, e o padrão de Edge Function com IA (`mindagent-chat`) também.
Repositório novo separaria o código da inteligência que ele consome.
Descarta: repo `treble-inbound-sales-agent` e projeto Supabase novo
(itens 1 e 27 da ordem original). Revisável se o produto crescer.

**D-6 — PDF/base de conhecimento nativa vira fallback, nunca caminho crítico.**
Por quê: conhecimento congelado desatualiza; mas se a Edge Function cair,
o bot não pode ficar mudo. `knowledge/` guarda um documento **gerado por
script** a partir do Supabase para o agente nativo de contingência.
Descarta: alimentação manual de PDF como plano principal.

**D-7 — Um único agente inbound na V1.**
Por quê: mesma conclusão do plano original — especializar
(abandono, outbound, pós-compra) só com razão funcional, depois da v0.1.

**D-8 — Testes rodam contra a Edge Function, sem WhatsApp no meio.**
Por quê: os 13 casos de `04_TESTS.md` viram script executável
(`tests/`); regressão é um comando, não uma tarde de conversas manuais.
O teste end-to-end via WhatsApp valida só a integração, não o comportamento.

**D-9 — Venda pela Eduzz; um link de checkout por categoria.** (2026-08-21)
`tickets.checkout_url` guarda o link por categoria; verificação de compra
e abandono via API/webhooks Eduzz (fase 2 da construção).

**D-10 — Handoff para os vendedores no inbox do Treble.** (2026-08-21)
O fluxo do Treble tem rota fixa de transferência; o agente prepara resumo
da conversa nas variáveis de sessão antes de transferir.

**D-11 — O "master router" é função, não frota.** (2026-08-21)
O desenho antigo previa um agente roteador no Treble triando B2C / B2B /
cliente-suporte antes de passar a agentes separados. Na arquitetura nova o
roteamento acontece em três camadas: (1) entrada determinística no fluxo do
Treble (origem da campanha/link pré-preenche `audience`); (2) classificação
a cada turno como primeiro passo do cérebro único, que troca de playbook
(prompt + tools) sem trocar de agente — o lead que muda de assunto no meio
não perde contexto; (3) handoff para a fila humana certa (vendedor B2C,
time B2B, suporte). Playbook vira agente separado só quando os dados de
`treble.conversations.audience` justificarem.
Descarta: agente roteador dedicado e frota de agentes na V1 (coerente com D-7).

**D-12 — Reusar o schema `mind`; criar só o que falta.** (2026-08-21)
A inspeção do banco mostrou que a Fase 1 planejada já existia em grande
parte: `mind.offers` é a tabela de ingressos (código, valor, lote,
checkout_url, elegibilidade — vazia, aguardando dados), `mind.policies` e
`mind.event_rules` cobrem políticas e regras textuais, `mind.organization_content`
recebe o FAQ, e `mind.knowledge_documents/chunks` já é a base RAG.
Criados apenas: schema `treble` (conversations + messages, RLS sem policies
— só service role), `mind.coupons` e `mind.commercial_rules`
(migration `20260821_treble_inbound_mvp.sql`, aplicada em 2026-08-21).
Guardrails nascem seguros: sem regra ativa liberando, desconto e menção a
cupom são proibidos por default.
Descarta: as tabelas `tickets`, `faq` e `event_info` previstas nos docs —
substituídas pelos equivalentes que já existiam.

**D-13 — Desconto de grupo é sempre pelos tiers percentuais.** (2026-08-21, Adriana)
Existiam dois mecanismos na Eduzz: produtos "Grupo VIP" com valor fixo
(R$250/500 off) e os `pricing_tiers` percentuais (5–9: 10% · 10+: 20% ·
15+: 30% · 20+: 35%). Decisão da Adriana: o bot cita só os tiers e
transfere grupo para vendedor fechar. As ofertas de grupo de valor fixo
ficam `ativo=false, publico=false` e a sync nunca as reativa.

**D-14 — Cérebro v0.1: contexto completo por turno, sem loop de tools.** (2026-08-21)
Como o conjunto de dados comerciais é pequeno (ofertas vigentes + próximo
lote + regras + políticas + FAQ), o v0.1 injeta o contexto oficial inteiro
a cada turno (RPC `treble_agent_context`) e faz UMA chamada ao LLM com
saída estruturada — cabe no limite de 10 s do webhook do Treble. Guardrail
extra em código: preço "R$ X" na resposta que não exista no contexto
derruba o turno para handoff. Loop de tool-calling fica para quando o
contexto crescer (ex.: agenda completa).

**D-15 — Em B2B, o agente municia; não transfere.** (2026-08-22, Adriana)
A análise das conversas dos últimos dois meses mostrou 53 leads travados em
"verba da empresa" e 59 perguntando espontaneamente sobre grupo. Quem diz
"preciso da aprovação do diretor" não quer um vendedor: quer argumento para
defender a compra lá dentro. O agente passa a informar o tier de desconto na
primeira resposta sobre grupo, montar a conta e entregar o racional; o
consultor entra por necessidade (contrato, nota fiscal, condição fora da
regra) ou a pedido.
Revisa a metade "transfere grupo para vendedor fechar" da D-13 — os tiers
percentuais continuam valendo integralmente. Mudou em três lugares que
precisavam andar juntos: `treble.prompts.playbook_b2b`, o `config.acao` da
regra `desconto_por_volume`, e `mindagent_sync_offers`, que reescrevia a
regra a cada 30 minutos e desfazia a mudança sozinha.

**D-16 — Conta de grupo é calculada no banco, não pelo LLM.** (2026-08-22)
Descoberto testando a D-15: o guardrail de preço derrubou a primeira resposta
de grupo, e com razão — R$ 2.078 (20% off do VIP) não existia em lugar nenhum
dos dados oficiais, então era indistinguível de preço inventado. A RPC
`mind_precos_por_volume()` cruza `mind.offers` × tiers e entrega valor com
desconto, economia e parcelamento prontos no contexto (coerente com D-3).
O guardrail passou a aceitar também múltiplo inteiro (2 a 60) de preço
oficial: total de grupo é multiplicação, não invenção.

**D-17 — A origem (botão de entrada) é conceito de primeira classe.** (2026-08-22, Adriana)
`mind.origens` guarda, por botão de cada site: o site (que vira `utm_source`),
o campo oculto do formulário do HubSpot, a mensagem de abertura do bot e a
audiência sugerida. O canal define o `utm_medium` — Treble = `chatbot`,
concierge do site = `chatbot_concierge` — e o código do botão vira
`utm_content`. `treble.conversations.origem_codigo` grava de onde a conversa
veio (primeira gravação vence). A tabela nasce vazia: a lista de botões é
conteúdo aprovado, não inventado.
Descarta: `utm_source` fixo por canal (o modelo anterior, que não distinguia
Mind Summit de Institute de Dash).

**D-18 — A janela de urgência é de 7 dias, e a contagem sai do banco.** (2026-08-22, Adriana)
Os lotes viram sempre no mesmo dia da semana (hoje, quinta). A comunicação
da virada começa exatamente 7 dias antes, no mesmo dia da semana, e conta
7, 6, 5… até o último dia. Fora dessa janela o agente **não** menciona
virada, contagem nem aumento: prazo distante lido como urgência soa a
pressão inventada. `mind_virada_de_lote()` devolve dias restantes, se a
janela está aberta, o dia da semana e quanto cada categoria sobe — contar
data é onde o LLM erra e onde o erro não é auditável. A janela é
configurável em `treble.config.janela_urgencia_dias`.

**D-19 — Escassez de categoria é campo, não dedução.** (2026-08-22, Adriana)
"Quando o lote vira, quem estava em dúvida corre, e a categoria pode não
ficar mais disponível" só vale dito quando for verdade. `mind.offers.procura`
(`normal` / `alta` / `ultimas_vagas`) controla isso por categoria; sem o
campo dizer, o agente não insinua. VIP e Prime entram como `alta` por
autorização dela. Nunca prometer esgotamento em data, nunca inventar número
de vagas.

**D-20 — A UTM original sobrevive até o checkout; o bot não a sobrescreve.** (2026-08-22, Adriana)
O WhatsApp quebra a cadeia de atribuição (não existe query string numa
conversa). O site registra a UTM em `mind.utm_sessoes` via
`mind_utm_registrar()`, recebe um token de 8 caracteres e o embute no texto
pré-preenchido do `wa.me` (`[ref ab12cd34]`). O cérebro lê, resolve, grava
em `treble.conversations.utm`, apaga o token do texto — o lead não escreveu
aquilo — e o contexto já entrega `checkout_url` com a atribuição embutida.
No checkout a UTM original vai **intacta**: `utm_source=google` continua
`google`. Sobrescrever com "mindsummit" tiraria da mídia paga o crédito da
venda que ela gerou. A camada do bot viaja em parâmetros próprios
(`mind_canal`, `mind_origem`, `mind_conversa`) que não disputam com os
`utm_`; `gclid`/`fbclid` passam adiante para o Google e a Meta fecharem a
conversão com o clique.
Descarta: `utm_source` do canal no checkout (o modelo da D-17 continua
valendo para links de material, onde a pergunta é outra).

**D-21 — Um fluxo no Treble para os cinco botões; a mensagem de abertura vive no banco.** (2026-08-22)
O documento de mensagens do site previa "direcionar bot B2B", "bot roteador"
e "bot atendimento" — desenho da época da frota de agentes. Com o cérebro
único isso vira `mind.origens.audiencia_sugerida`, e a mesma conversa muda
de postura sem perder contexto. As cinco mensagens de abertura, de
encerramento e de descadastro ficam em `mind.origens`, não no painel do
Treble: mudar uma mensagem passa a ser um UPDATE, não uma edição de fluxo
em cinco lugares.

**D-22 — Palestrante fica em tabela separada; o papel é da ligação.** (2026-08-22, Adriana)
Pergunta dela: cadastrar palestrante à parte com a mini bio, ou junto da
palestra? Separado, e por um motivo concreto: os 42 palestrantes aparecem
em 67 sessões — Amy Edmondson em 3, Carla Tieppo em 3 —, então a bio junto
da palestra viraria 3 cópias da mesma bio para desencontrar. `mind.speakers`
guarda a pessoa (bio, credencial, frase de card, foto), `mind.sessions`
guarda a sessão, e `mind.session_speakers` liga as duas com **papel**
(palestrante / mediação / apresentação / convidado). O papel é da ligação
porque Denize Savi media um painel e palestra em outro.
`mind.sessions.ingressos` é coluna nova e é o que faltava para o agente
dizer "esse workshop é VIP e Prime" sem deduzir do nome da sala.

**D-23 — Uma fonte por fato: as bios duplicadas em knowledge_documents saíram.** (2026-08-22, Adriana)
Havia 42 documentos `tipo_conteudo = 'palestrante'` em
`mind.knowledge_documents` com as mesmas bios de `mind.speakers` (conferido
por md5: idênticas byte a byte). Duas cópias do mesmo fato é uma que
desatualiza sozinha. Os 42 documentos e seus chunks foram apagados; o
agente já lia palestrante de `mind.speakers` via `mindagent_chat_search`.

**D-24 — Produto é coluna, não premissa.** (2026-08-22, Adriana)
"O Mind Summit 2026 é um produto. Logo ele vai morrer e a gente vai começar
a conversar sobre outros. Tem que já nascer pronto." `mind.produtos` passa a
existir e `produto_codigo` entra em conteúdo, materiais, origens, regras
comerciais, políticas, prompts e conversas. NULL significa "vale para
qualquer produto" — é o caso do tom de voz, das políticas e dos playbooks,
porque vender é vender; muda o que se vende. `treble.config.produto_padrao`
diz de que produto o bot fala quando a conversa não indica outro.

**D-25 — O agente sabe onde está no calendário do produto.** (2026-08-22, Adriana)
Sem isso o bot tenta vender um Summit que já aconteceu. `mind_calendario()`
devolve a fase (`venda` · `semana_do_evento` · `acontecendo` · `encerrado`),
os dias que faltam e o que fazer em cada uma. Depois do evento a mesma
pergunta deixa de ser venda e vira atendimento — e, se houver próxima
edição cadastrada na mesma linha, o agente redireciona para ela em vez de
dizer que acabou. Contar dias a partir de datas é onde o LLM erra: o número
vem pronto, como na D-18.

**D-26 — Imagem vai para bucket, não para o repositório.** (2026-08-22)
As 42 fotos vieram em PNG (9,3 MB). Commitá-las no repositório do worker
seria peso morto e mais uma cópia para desencontrar. Vão para o bucket
público `mind-assets` (convertidas em webp, 570 KB no total), e
`mind_foto_url()` resolve `asset_path` para a URL pública com fallback para
o `foto_url` antigo — ninguém fica sem imagem durante a troca.
