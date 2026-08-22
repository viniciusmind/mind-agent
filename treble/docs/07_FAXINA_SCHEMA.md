# Faxina do schema `mind` — decisão tabela a tabela

Inventário completo e o raciocínio de cada uma:
https://claude.ai/code/artifact/b579d631-09ab-4bab-a812-d26e1d2ca38a

O critério que a Adriana e eu usamos em cada linha **não** é "isso é do
Summit?" (quase tudo é, hoje), e sim: **isso perde o sentido fora de um
evento?** Se perde, é mecânica de evento. Se sobrevive, atravessa produtos.

Estado: 1 de 30 decididas.

---

## 1. `mind.commercial_rules` — FICA · escopo Summit 2026

4 linhas · já tem `produto_codigo` · lida por `treble_agent_context_base`,
`mind_precos_por_volume` e `mindagent_sync_offers`.

O que guarda: o que o agente pode e não pode fazer numa venda.

| chave | config |
|---|---|
| `desconto_espontaneo` | `{permitido: false}` |
| `mencionar_cupom_nao_solicitado` | `{permitido: false}` |
| `insistencia_apos_desinteresse` | `{max_retomadas: 1}` |
| `desconto_por_volume` | tiers 5–9: 10% · 10+: 20% · 15+: 30% · 20+: 35% |

**Decisão da Adriana:** é política de venda do Mind Summit. As quatro ficam
em `produto_codigo = 'mind-summit-2026'` — que é o estado atual. Nada a
migrar.

Eu havia proposto separar as três primeiras (postura de venda, valeriam para
qualquer produto) da quarta (preço, essa sim do Summit). A Adriana decidiu
tratar as quatro como política do produto.

**Consequência registrada:** quando Institute ou Dash entrarem, cada um
precisa das suas próprias quatro linhas — inclusive as de postura. Um
produto novo sem elas nasce podendo inventar desconto, porque o guardrail é
"sem regra ativa liberando, não existe desconto", e a ausência de regra é
lida como ausência de permissão. Ou seja: falha segura, mas o agente também
fica sem os tiers de grupo.
