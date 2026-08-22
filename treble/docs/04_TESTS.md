# Testes — casos críticos e critérios

Regra: **nenhum ajuste de prompt sem rodar a regressão completa.** Todo
problema encontrado é classificado antes de corrigido:

- **P0** — não funciona (erro, loop, sem resposta)
- **P1** — comportamento comercial errado (preço/info inventada,
  desconto indevido, checkout errado, handoff que não acontece)
- **P2** — experiência ruim (tom, prolixidade, pergunta demais)
- **P3** — melhoria futura

Só P0 e P1 bloqueiam a v0.1.

## Casos mínimos (input → comportamento esperado)

| # | Caso | Comportamento esperado |
|---|---|---|
| 1 | "Quero o MIND" | Confirma, envia checkout MIND (link da tabela), registra `checkout_enviado` |
| 2 | "Quero o VIP" | Idem, checkout VIP |
| 3 | "Quero o PRIME" | Idem, checkout PRIME |
| 4 | "Não sei qual ingresso" | Faz no máx. 2 perguntas de perfil, recomenda 1 categoria com justificativa, oferece comparação |
| 5 | "Achei caro" | Trata objeção com argumento permitido; **não** oferece desconto se `commercial_rules` não autorizar |
| 6 | "Tem desconto?" | Consulta regra; responde só o autorizado; sem regra → não inventa, segue venda ou escala |
| 7 | "Tenho um cupom X" | `check_coupon`; válido → aplica no discurso; inválido → informa sem constranger |
| 8 | "Quem vai palestrar?" | Responde com dados da fonte (bootstrap); nunca inventa nome |
| 9 | "Quando/onde é?" | `event_info` correto (16–17/09/2026, São Paulo Expo) |
| 10 | "Já comprei" | Verifica na Eduzz quando possível; agradece, tira dúvida prática, encerra `ja_comprou`; não tenta vender de novo |
| 11 | "Quero falar com alguém" | Handoff imediato ao inbox com resumo nas variáveis; sem tentar segurar |
| 12 | "Quero me descadastrar" | Confirma e executa opt-out; encerra `descadastrado` |
| 13 | Pergunta fora de escopo | Redireciona com educação para o tema Summit; não opina fora do escopo |

Casos adicionais a criar junto com as regras comerciais reais:
"minha empresa paga", negociação em volume, erro de pagamento,
mensagem de áudio/imagem, lead irritado, insistência após "não".

## Execução

- **Fase cérebro** (Checkpoint 2): script em `tests/` chama a Edge Function
  com cada caso e valida o comportamento observado
  (`esperado → observado → passou/falhou → motivo`). Resultados registrados
  aqui, por data.
- **Fase end-to-end** (Checkpoint 3): os mesmos casos pelo WhatsApp real,
  validando só a integração Treble ↔ cérebro ↔ Treble.

## Resultados

_(vazio — nenhuma execução ainda)_
