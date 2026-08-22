# Integração Treble — contrato e roteiro de configuração

> Status (2026-08-21): **cérebro v0.1 no ar e testado isolado** — Edge
> Function `treble-inbound-agent`. Falta só a montagem do fluxo no painel
> do Treble (roteiro abaixo).

## Roteiro de montagem no painel (fluxo de teste)

URL do webhook (o `TOKEN` fica fora do repositório — pedir no chat da
sessão ou rodar `select public.treble_agent_token()`):

```
https://ymnmotgglsrxmjmonwjz.supabase.co/functions/v1/treble-inbound-agent?token=TOKEN
```

1. **Bloco de entrada** (mensagem simples): saudação curta. Ativar
   *salvar resposta* com o nome de variável **`mensagem`** (texto).
2. Na saída desse bloco, **adicionar o webhook** com a URL acima
   (método POST). O corpo que o Treble envia já contém a variável salva e
   o `session_external_id`; a função aceita os dois formatos.
3. **Bloco de resposta** (mensagem simples) exibindo `{{resposta_ia}}`,
   também com *salvar resposta* em `mensagem` e o MESMO webhook na saída —
   apontando para ele mesmo (loop da conversa).
4. **Rota de handoff**: condição `needs_human = true` → bloco de
   transferência para o inbox dos vendedores (antes do loop).
5. Publicar e testar no Playground/WhatsApp.

A função devolve `user_session_keys`: `resposta_ia`, `needs_human`,
`intent`, `audience`, `checkout_sent`.

## O que o v0.1 já faz (testado)

- Preço/lote/parcelamento reais (fonte sincronizada a cada 30 min),
  urgência verdadeira da virada de lote
- Roteador b2c/b2b/suporte (D-11); grupo → tiers percentuais + handoff (D-13)
- Não inventa desconto (regras em `mind.commercial_rules`); guardrail em
  código derruba preço não-oficial para handoff
- Persiste tudo em `treble.conversations`/`messages` com estado e desfecho

## Mecanismo (documentação oficial do Treble)

- **Webhook de resposta**: cada bloco de mensagem do fluxo salva a resposta
  do usuário em variável e envia POST ao nosso endpoint com a mensagem,
  as variáveis e o `session_external_id`. Resposta em < 10 s volta ao fluxo.
- **`[REQUEST_TRIGGER]`**: bloco que pausa a conversa até o nosso servidor
  chamar `POST /session/{session_external_id}/update` com a resposta e
  `user_session_keys`.
- Referências: guia "Integrate Your Own AI in Treble", páginas de webhooks
  e endpoints em help.treble.ai (API key na seção Developers do painel).

## Fluxo fino no Conversation Builder

```
entrada (saudação + salvar resposta)
  → webhook → [REQUEST_TRIGGER] → mensagem com {{resposta_do_cerebro}}
  → loop de conversa
  rotas fixas: needs_human=true → transferir ao inbox (vendedores)
               opt-out → descadastro
```

## Variáveis de sessão espelhadas

`intent` · `stage` · `needs_human` · `checkout_sent` — o estado completo
vive na tabela `conversations` do Supabase.

## Segurança

- `TREBLE_API_KEY` e `TREBLE_WEBHOOK_SECRET`: só nas env vars da Edge
  Function. Nunca no repositório, nunca em chat.
- O webhook valida a origem antes de processar.
