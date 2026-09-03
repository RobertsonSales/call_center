-- ============================================================================
-- Migração 002 — Integração com a API do WhatsApp (Caminho A — Meta direta)
-- Grupo Labmedic — Sistema de Atendimento Técnico Interno
--
-- Referência: Proposta Técnica (cap. 6) e Fluxo de Conversas Simultâneas.
-- Aditiva: preserva integralmente atendimentos, interacoes, clientes,
-- equipamentos, linhas, categorias_encerramento já existentes.
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1. whatsapp_numeros — liga cada Linha já cadastrada às credenciais técnicas
--    do número correspondente na plataforma da Meta.
-- ----------------------------------------------------------------------------
create table if not exists whatsapp_numeros (
  id uuid primary key default gen_random_uuid(),
  linha_id uuid not null references linhas(id),
  waba_id text not null,
  phone_number_id text not null unique,
  token_secret_ref text, -- referência textual ao segredo (o token em si NUNCA fica aqui)
  status_verificacao text not null default 'pendente'
    check (status_verificacao in ('pendente', 'verificado', 'rejeitado')),
  ativo boolean not null default true,
  criado_em timestamptz not null default now()
);

create index if not exists idx_whatsapp_numeros_linha on whatsapp_numeros(linha_id);

-- ----------------------------------------------------------------------------
-- 2. templates_whatsapp — catálogo dos templates aprovados pela Meta
-- ----------------------------------------------------------------------------
create table if not exists templates_whatsapp (
  id uuid primary key default gen_random_uuid(),
  nome_meta text not null unique,
  categoria text not null check (categoria in ('utilidade', 'autenticacao', 'marketing')),
  idioma text not null default 'pt_BR',
  status_aprovacao text not null default 'em_analise'
    check (status_aprovacao in ('em_analise', 'aprovado', 'rejeitado')),
  uso_sugerido text,
  criado_em timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 3. contatos_cliente — pessoa específica do cliente que solicita o
--    atendimento (distinta da unidade em si, já cadastrada em "clientes")
-- ----------------------------------------------------------------------------
create table if not exists contatos_cliente (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references clientes(id),
  nome text not null,
  telefone text not null,
  cargo_setor text,
  email text,
  ativo boolean not null default true,
  criado_em timestamptz not null default now()
);

create index if not exists idx_contatos_cliente_cliente on contatos_cliente(cliente_id);
create index if not exists idx_contatos_cliente_telefone on contatos_cliente(telefone);

-- ----------------------------------------------------------------------------
-- 4. Novas colunas em atendimentos
-- ----------------------------------------------------------------------------
alter table atendimentos
  add column if not exists canal text not null default 'manual'
    check (canal in ('manual', 'whatsapp_api')),
  add column if not exists contato_cliente_id uuid references contatos_cliente(id),
  add column if not exists janela_24h_expira_em timestamptz;

-- agente_id precisa aceitar NULL: uma solicitação recebida de um número sem
-- atendimento aberto (cenário B do Fluxo de Conversas Simultâneas) é criada
-- automaticamente pelo webhook, antes de qualquer técnico "assumir" o caso.
alter table atendimentos
  alter column agente_id drop not null;

create index if not exists idx_atendimentos_canal on atendimentos(canal);
create index if not exists idx_atendimentos_nao_assumidos
  on atendimentos(status) where agente_id is null;

-- ----------------------------------------------------------------------------
-- 5. mensagens_whatsapp — log bruto de cada mensagem trocada pela API,
--    complementar à interacoes (que continua sendo a visão "humana")
-- ----------------------------------------------------------------------------
create table if not exists mensagens_whatsapp (
  id uuid primary key default gen_random_uuid(),
  atendimento_id uuid not null references atendimentos(id),
  interacao_id uuid references interacoes(id),
  wa_message_id text unique,
  direcao text not null check (direcao in ('enviada', 'recebida')),
  tipo_conteudo text not null default 'texto'
    check (tipo_conteudo in ('texto', 'imagem', 'audio', 'documento', 'template')),
  status text not null default 'enviada'
    check (status in ('enviada', 'entregue', 'lida', 'falhou')),
  payload_bruto jsonb,
  criado_em timestamptz not null default now()
);

create index if not exists idx_mensagens_whatsapp_atendimento on mensagens_whatsapp(atendimento_id);
create unique index if not exists idx_mensagens_whatsapp_wa_id on mensagens_whatsapp(wa_message_id) where wa_message_id is not null;

-- ----------------------------------------------------------------------------
-- 6. atendimento_eventos — log estruturado de mudanças de status/atribuição
--    (transferência de setor/atendente, "assumir atendimento" etc.)
-- ----------------------------------------------------------------------------
create table if not exists atendimento_eventos (
  id uuid primary key default gen_random_uuid(),
  atendimento_id uuid not null references atendimentos(id),
  agente_id uuid references agentes(id),
  tipo_evento text not null, -- ex.: 'assumido', 'reatribuido', 'reaberto'
  valor_anterior text,
  valor_novo text,
  criado_em timestamptz not null default now()
);

create index if not exists idx_atendimento_eventos_atendimento on atendimento_eventos(atendimento_id);

-- ----------------------------------------------------------------------------
-- 7. RLS das tabelas novas — mesmo padrão já usado no restante do sistema
--    (leitura para qualquer agente autenticado; escrita conforme o caso)
-- ----------------------------------------------------------------------------
alter table whatsapp_numeros   enable row level security;
alter table templates_whatsapp enable row level security;
alter table contatos_cliente   enable row level security;
alter table mensagens_whatsapp enable row level security;
alter table atendimento_eventos enable row level security;

drop policy if exists "leitura_autenticados_whatsapp_numeros" on whatsapp_numeros;
create policy "leitura_autenticados_whatsapp_numeros" on whatsapp_numeros
  for select using (auth.role() = 'authenticated');
drop policy if exists "leitura_autenticados_templates_whatsapp" on templates_whatsapp;
create policy "leitura_autenticados_templates_whatsapp" on templates_whatsapp
  for select using (auth.role() = 'authenticated');
drop policy if exists "leitura_autenticados_contatos_cliente" on contatos_cliente;
create policy "leitura_autenticados_contatos_cliente" on contatos_cliente
  for select using (auth.role() = 'authenticated');
drop policy if exists "escrita_autenticados_contatos_cliente" on contatos_cliente;
create policy "escrita_autenticados_contatos_cliente" on contatos_cliente
  for insert with check (auth.role() = 'authenticated');
drop policy if exists "leitura_autenticados_mensagens_whatsapp" on mensagens_whatsapp;
create policy "leitura_autenticados_mensagens_whatsapp" on mensagens_whatsapp
  for select using (auth.role() = 'authenticated');
drop policy if exists "leitura_autenticados_atendimento_eventos" on atendimento_eventos;
create policy "leitura_autenticados_atendimento_eventos" on atendimento_eventos
  for select using (auth.role() = 'authenticated');

-- gestão de whatsapp_numeros/templates_whatsapp (cadastro/edição): só supervisor/admin_pleno
drop policy if exists "gestao_supervisor_whatsapp_numeros" on whatsapp_numeros;
create policy "gestao_supervisor_whatsapp_numeros" on whatsapp_numeros
  for all using (
    exists (select 1 from agentes a where a.id = auth.uid() and a.papel in ('supervisor','admin_pleno'))
  );
drop policy if exists "gestao_supervisor_templates_whatsapp" on templates_whatsapp;
create policy "gestao_supervisor_templates_whatsapp" on templates_whatsapp
  for all using (
    exists (select 1 from agentes a where a.id = auth.uid() and a.papel in ('supervisor','admin_pleno'))
  );

-- observação: as Edge Functions (whatsapp-webhook, whatsapp-enviar, whatsapp-midia)
-- usam a service_role key do Supabase para gravar diretamente nas tabelas,
-- contornando a RLS por design — a segurança desse caminho está em manter a
-- service_role key exclusivamente nos segredos das próprias funções.

commit;

