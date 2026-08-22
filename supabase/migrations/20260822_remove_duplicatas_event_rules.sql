-- Uma fonte por fato, passo 1 (Adriana aprovou apagar as duplicações).
--
-- Quatro regras de mind.event_rules eram cópia byte a byte de um
-- knowledge_document (comparado ignorando espaço e caixa). Duas cópias do
-- mesmo fato é uma que desatualiza sozinha.
--
-- Quem vence: mind.knowledge_documents. É de lá que os agentes leem — o
-- Treble monta `faq` e `conteudo_aprovado` dali, e o concierge usa os
-- chunks. mind.event_rules não é lida por nenhuma função do banco além da
-- de gravação do admin, e não aparece em lugar nenhum do repositório.
--
-- As quatro apagadas, e o documento onde o mesmo texto continua vivo:
--   assentos-arena-mind  -> "Tem assento marcado?"
--   diferenca-mind-vip   -> "Qual a diferença entre Mind e VIP?"
--   masterclasses-prime  -> "O que são as Masterclasses Prime?"
--   traducao-simultanea  -> "Haverá tradução simultânea?"
--
-- NÃO são duplicatas e ficam (7): como-chegar, fila_de_espera, gravacoes,
-- reserva_expira, reserva-workshops-masterclasses, sessoes-remotas,
-- vagas_limitadas.

delete from mind.event_rules r
 where exists (
   select 1 from mind.knowledge_documents k
    where regexp_replace(lower(trim(k.corpo)), '\s+', ' ', 'g')
        = regexp_replace(lower(trim(r.texto)), '\s+', ' ', 'g'));
