# Requisitos — Agente Inbound de Vendas

> Extraídos do levantamento feito pela Adriana (conversas de definição do
> bot). A estrutura técnica foi redesenhada; as necessidades de negócio
> abaixo são o contrato.

## Objetivo funcional

Conduzir a conversa inteira: entender a intenção → responder/qualificar →
identificar barreira → tratar objeção → recomendar categoria → enviar
checkout → confirmar resultado. Vender é o fim; informar é o meio.

## Quem entra no fluxo

Lead novo · lead já impactado por campanha · comparação de ingressos ·
dúvida prática · objeção de preço · lead com cupom · abandono de carrinho ·
quem já comprou · pedido de humano · pedido de descadastro.

## Desfechos aceitos como sucesso

Compra concluída · checkout enviado · lead qualificado para follow-up ·
transferência correta para humano · encerramento porque já comprou ·
descadastramento. **Conversa sem desfecho registrado é bug.**

## Intenções a reconhecer

`comprar` · `comparar_ingressos` · `preco` · `cupom` · `palestrantes` ·
`programacao` · `local` · `empresa_paga` · `ja_comprei` · `suporte` ·
`humano` · `descadastrar` · `fora_de_escopo`

## Conhecimento / Decisão / Ação (padrão por tema)

- **Conhecimento**: o que está nas tabelas (ex.: VIP custa X no lote atual).
- **Decisão**: como usa (ex.: recomendar VIP quando o perfil justificar).
- **Ação**: o que pode fazer (ex.: enviar o link de checkout VIP da Eduzz).

## Permissions (o que o agente pode fazer)

- Informar preço, lote, benefícios e diferenças entre MIND, VIP e PRIME
- Recomendar uma categoria com justificativa
- Enviar link de checkout Eduzz da categoria escolhida
- Validar cupom existente (`check_coupon`)
- Registrar qualificação e objeção do lead
- Transferir para vendedor humano no inbox do Treble
- Encerrar e descadastrar quando pedido

## Constraints (o que nunca pode fazer)

- Inventar preço, benefício, palestrante, data ou política — se a tool não
  retornou, diz que vai confirmar e aciona handoff
- Oferecer desconto/cupom fora do que `commercial_rules` autoriza
- Insistir após sinal claro de desinteresse (limite definido nas regras)
- Prometer em nome do Mind o que não está nas tabelas
- Discutir temas fora do escopo do Summit (redireciona com educação)
- Ignorar pedido de humano ou de descadastro

## Escalation (handoff para vendedor no Treble)

Casos objetivos: erro de pagamento · situação fora da política comercial ·
pedido explícito de humano · negociação especial (ex.: compra em volume,
empresa pagando com condições próprias) · dúvida que as tools não resolvem ·
reclamação sensível. No handoff, o vendedor recebe resumo: intenção,
categoria de interesse, objeção, estágio.

## Objeções mapeadas (tratamento detalhado virá com as regras comerciais)

Preço ("achei caro") · "quero desconto" · "minha empresa paga" ·
timing ("vou decidir depois") · comparação com outros eventos ·
insegurança sobre valor ("vale a pena?").

## Tom de voz

**Pendente**: material de referência do Mind (Adriana vai enviar).
Baseline até lá: caloroso, direto, consultivo; respostas curtas (WhatsApp);
no máximo uma pergunta por mensagem; ritmo comercial sem pressão.

## Variáveis por conversa

`lead_name` · `intent` · `ticket_interest` · `objection` · `coupon_status` ·
`checkout_sent` · `purchase_status` · `needs_human` · `stage`

Registro completo no Supabase (`conversations`); espelho mínimo nas
variáveis de sessão do Treble.
