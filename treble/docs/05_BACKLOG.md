# Backlog — fora da V1, registrado para não perder

- **Agentes especializados**: abandono de carrinho (gatilho por webhook
  Eduzz), outbound, recuperação de leads frios, pós-compra, suporte.
- **Mind Intelligence API**: expor a inteligência como camada HTTP pública
  (`Treble → Mind Intelligence API → Supabase`) quando AI Coach, app e
  outbound precisarem da mesma fonte. Na V1 é interna à Edge Function (D-2).
- **Integração HubSpot**: gravar lead qualificado, objeção e desfecho no
  CRM automaticamente (a conexão já existe na conta).
- **Webhook Eduzz → Supabase**: compra confirmada e carrinho abandonado
  atualizando `conversations`/`purchase_status` em tempo real, permitindo
  follow-up automático pós-checkout.
- **Pipeline da base de fallback**: regenerar `knowledge/` automaticamente
  (cron/n8n) quando as tabelas mudarem, avisando quando é preciso re-subir
  no painel do Treble.
- **RAG sobre conteúdo longo**: descrições extensas de palestras/temas, se
  o volume justificar embeddings além das tabelas estruturadas.
- **Dashboard de métricas**: taxa de resolução sem humano, conversão por
  categoria, objeção mais frequente, tempo até checkout, abandono por etapa.
- **Multi-idioma** (se o Summit tiver público internacional).
- **Detecção de mídia**: áudio transcrito, comprovante de pagamento como
  imagem.
