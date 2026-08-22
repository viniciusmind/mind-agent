-- O número do lead (vindo do webhook do Treble) passa a ser guardado em
-- claro além do hash: é dado de atendimento/venda (follow-up, handoff,
-- futuro vínculo com HubSpot/Eduzz). Descadastro apaga a conversa.
-- Aplicada em 2026-08-21 (migration "treble_conversations_telefone").
alter table treble.conversations add column if not exists telefone text;
-- treble_agent_start atualizado para persistir telefone (e manter hash).
