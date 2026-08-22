# Estado do projeto — Agente Inbound de Vendas (Treble)

> Última atualização: 2026-08-21 · Fase: **decisão concluída, construção não iniciada**

## O que este projeto é

Agente de vendas inbound do Mind Summit 2026 no WhatsApp, operando sobre o
Treble, com o Supabase como fonte da verdade. Converte conversas iniciadas
por leads em vendas concluídas: responde dúvidas, identifica intenção,
trata objeções, recomenda a categoria certa (MIND / VIP / PRIME) e leva ao
checkout — ou a um humano, quando é o caso.

## O que já existe (herdado, não construir de novo)

| Peça | Onde | Estado |
|---|---|---|
| Projeto Supabase `mind-agent` | `ymnmotgglsrxmjmonwjz` (sa-east-1) | ativo |
| Dados de agenda/palestrantes | Edge Function `mindagent-bootstrap` (10 temas, 67 sessões, 44 palestrantes) | ativo |
| Padrão de agente com IA | Edge Function `mindagent-chat` (concierge do site) | ativo |
| Teste Treble→Supabase | Edge Function `treble-find-location` (v9) | funciona, mas segue o modelo descartado (um endpoint por pergunta, chamado pelo agente nativo do Treble) |
| Painel admin | `admin/` + tabelas `mind_admin_*` | ativo |

## O que está decidido

Arquitetura congelada em [`01_ARCHITECTURE.md`](01_ARCHITECTURE.md);
decisões e justificativas em [`03_DECISIONS.md`](03_DECISIONS.md). Resumo:
**um único cérebro** (Edge Function `treble-inbound-agent`) recebe as
mensagens via webhook do Treble, consulta o Supabase diretamente a cada
turno e devolve a resposta. O fluxo no Treble é fino: entrada, webhook,
handoff humano, opt-out.

## Pendências que bloqueiam a construção

- [x] **Plataforma de venda**: Eduzz — cada categoria (MIND/VIP/PRIME) tem
      o próprio link de checkout
- [x] **Destino do handoff humano**: vendedores já atendem no inbox do Treble
- [ ] **Regras comerciais reais**: valores, política de cupom/desconto,
      condições e exceções (Adriana vai enviar)
- [ ] **Tom de voz do Mind**: material de referência (Adriana vai enviar)
- [ ] **Roteamento de handoff**: quem atende B2B e suporte no inbox do
      Treble — filas separadas ou as mesmas pessoas? (ver D-11)
- [x] **API key do Treble**: guardada como secret `TREBLE_API_KEY` nas
      Edge Functions (2026-08-21); rotacionar no painel Developers do
      Treble antes do go-live

## Nota: CI de deploy do site (fora do escopo do bot, registrado aqui)

O Workers Builds da Cloudflare (worker `mind-agent`, conectado ao repo em
2026-08-21) falhava em todo push por dois problemas combinados: nome no
`wrangler.toml` divergente do worker (`mindagent` × `mind-agent`) e
ausência de comando de build no CI — o deploy rodava sem o `dist/`
existir. Correções no repositório: nome alinhado e passo `[build]` do
wrangler montando o `dist/` antes do upload (validado localmente
simulando o ambiente limpo do CI). Aguardando build verde para
confirmar o encerramento.

## Próximos passos (ordem completa em [`06_PLANO_EXECUCAO.md`](06_PLANO_EXECUCAO.md))

1. Criar as tabelas do MVP no projeto Supabase `mind-agent`
2. Popular com dados reais e validar as consultas sem IA no meio
3. Construir a Edge Function `treble-inbound-agent`
4. Testar o cérebro isolado (sem Treble) contra os casos de `04_TESTS.md`
5. Só então abrir o Treble e montar o fluxo fino
