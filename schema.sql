-- =====================================================================
-- CENTRAL DE ATENDIMENTO TÉCNICO — SCHEMA SUPABASE
-- =====================================================================
-- Execute este script inteiro no SQL Editor do seu projeto Supabase
-- (Project > SQL Editor > New query > colar > Run).
-- =====================================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------
-- 1) AGENTES (perfil vinculado ao usuário de autenticação do Supabase)
-- ---------------------------------------------------------------------
create table if not exists agentes (
  id         uuid primary key references auth.users(id) on delete cascade,
  nome       text not null,
  email      text not null,
  ativo      boolean not null default true,
  is_admin   boolean not null default false,   -- true = Supervisor (vê e gerencia todos os atendimentos)
  criado_em  timestamptz not null default now()
);

-- Cria automaticamente um registro em "agentes" quando um novo usuário
-- é criado no Supabase Auth (login e senha cadastrados no painel).
create or replace function public.handle_new_agente()
returns trigger
language plpgsql
security definer
as $$
begin
  insert into public.agentes (id, nome, email)
  values (new.id, coalesce(new.raw_user_meta_data->>'nome', new.email), new.email)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_agente();

-- ---------------------------------------------------------------------
-- 2) LINHAS — cada número de WhatsApp que gera protocolos
-- ---------------------------------------------------------------------
create table if not exists linhas (
  id         uuid primary key default gen_random_uuid(),
  numero     text not null unique,   -- formato E.164, ex: 5521999990000
  nome       text not null,          -- ex: "Linha Suporte Técnico 1"
  ativo      boolean not null default true,
  criado_em  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 3) ATENDIMENTOS (tickets / protocolos)
-- ---------------------------------------------------------------------
create sequence if not exists protocolo_seq;

create table if not exists atendimentos (
  id                  uuid primary key default gen_random_uuid(),
  protocolo           text unique not null default (
    'AT-' || to_char(now(), 'YYYYMMDD') || '-' || lpad(nextval('protocolo_seq')::text, 5, '0')
  ),
  linha_id            uuid references linhas(id),
  cliente_nome        text not null,
  cliente_telefone    text not null,   -- E.164, ex: 5521988887777
  equipamento         text,
  descricao_problema  text,
  status              text not null default 'aberto'
                        check (status in ('aberto','em_andamento','transferido','encerrado')),
  agente_id           uuid references agentes(id),
  criado_em           timestamptz not null default now(),
  atualizado_em       timestamptz not null default now()
);

create index if not exists idx_atendimentos_protocolo on atendimentos(protocolo);
create index if not exists idx_atendimentos_criado_em on atendimentos(criado_em);
create index if not exists idx_atendimentos_linha on atendimentos(linha_id);
create index if not exists idx_atendimentos_status on atendimentos(status);

create or replace function public.set_atualizado_em()
returns trigger language plpgsql as $$
begin
  new.atualizado_em = now();
  return new;
end;
$$;

drop trigger if exists trg_atendimentos_atualizado on atendimentos;
create trigger trg_atendimentos_atualizado
  before update on atendimentos
  for each row execute function public.set_atualizado_em();

-- ---------------------------------------------------------------------
-- 4) INTERAÇÕES — histórico de procedimentos/mensagens de cada protocolo
-- ---------------------------------------------------------------------
create table if not exists interacoes (
  id              uuid primary key default gen_random_uuid(),
  atendimento_id  uuid not null references atendimentos(id) on delete cascade,
  agente_id       uuid references agentes(id),
  tipo            text not null default 'procedimento'
                    check (tipo in ('procedimento','mensagem','nota_interna','transferencia','encerramento')),
  conteudo        text not null,
  criado_em       timestamptz not null default now()
);

create index if not exists idx_interacoes_atendimento on interacoes(atendimento_id);
create index if not exists idx_interacoes_criado_em on interacoes(criado_em);

-- ---------------------------------------------------------------------
-- 5) AUDITORIA POR LINHA — registro imutável de todo protocolo gerado
--    por cada número, para fins de auditoria (não é apagado nunca).
-- ---------------------------------------------------------------------
create table if not exists auditoria_linha (
  id              uuid primary key default gen_random_uuid(),
  linha_id        uuid references linhas(id),
  atendimento_id  uuid references atendimentos(id),
  protocolo       text not null,
  evento          text not null check (evento in ('criado','transferido','encerrado')),
  agente_id       uuid references agentes(id),
  detalhe         text,
  criado_em       timestamptz not null default now()
);

create index if not exists idx_auditoria_linha on auditoria_linha(linha_id);
create index if not exists idx_auditoria_protocolo on auditoria_linha(protocolo);
create index if not exists idx_auditoria_criado_em on auditoria_linha(criado_em);

-- Grava automaticamente em auditoria_linha sempre que um atendimento é
-- criado ou muda de status — assim a auditoria nunca depende do app.
create or replace function public.registrar_auditoria()
returns trigger language plpgsql as $$
begin
  if (tg_op = 'INSERT') then
    insert into auditoria_linha (linha_id, atendimento_id, protocolo, evento, agente_id)
    values (new.linha_id, new.id, new.protocolo, 'criado', new.agente_id);
  elsif (tg_op = 'UPDATE' and new.status is distinct from old.status) then
    if new.status = 'transferido' then
      insert into auditoria_linha (linha_id, atendimento_id, protocolo, evento, agente_id)
      values (new.linha_id, new.id, new.protocolo, 'transferido', new.agente_id);
    elsif new.status = 'encerrado' then
      insert into auditoria_linha (linha_id, atendimento_id, protocolo, evento, agente_id)
      values (new.linha_id, new.id, new.protocolo, 'encerrado', new.agente_id);
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_auditoria_insert on atendimentos;
create trigger trg_auditoria_insert
  after insert on atendimentos
  for each row execute function public.registrar_auditoria();

drop trigger if exists trg_auditoria_update on atendimentos;
create trigger trg_auditoria_update
  after update on atendimentos
  for each row execute function public.registrar_auditoria();

-- ---------------------------------------------------------------------
-- 6) RLS — cada agente só enxerga e gerencia os PRÓPRIOS atendimentos.
--    "linhas" e "agentes" continuam de leitura compartilhada, pois são
--    apenas cadastros de apoio (dropdown de linha, nome do agente nos
--    históricos) — nenhum dado de cliente vaza por eles.
-- ---------------------------------------------------------------------
alter table agentes         enable row level security;
alter table linhas          enable row level security;
alter table atendimentos    enable row level security;
alter table interacoes      enable row level security;
alter table auditoria_linha enable row level security;

-- Cadastros de apoio: leitura liberada a qualquer agente autenticado.
create policy "agentes autenticados leem agentes"    on agentes for select using (auth.role() = 'authenticated');
create policy "agentes autenticados leem linhas"     on linhas  for select using (auth.role() = 'authenticated');
create policy "agentes autenticados gerenciam linhas" on linhas for insert with check (auth.role() = 'authenticated');
create policy "agentes autenticados atualizam linhas" on linhas for update using (auth.role() = 'authenticated');

-- Atendimentos: só o agente dono do chamado (agente_id = auth.uid())
-- pode ver, criar ou atualizar. Um agente não enxerga o chamado de outro.
create policy "agente ve so os proprios atendimentos"
  on atendimentos for select using (agente_id = auth.uid());

create policy "agente cria atendimento como dono"
  on atendimentos for insert with check (agente_id = auth.uid());

create policy "agente atualiza so os proprios atendimentos"
  on atendimentos for update using (agente_id = auth.uid());

-- Interações: seguem a posse do atendimento ao qual pertencem — um
-- agente só lê/grava interações de um atendimento que é seu.
create policy "agente ve interacoes dos proprios atendimentos"
  on interacoes for select using (
    exists (
      select 1 from atendimentos a
      where a.id = interacoes.atendimento_id and a.agente_id = auth.uid()
    )
  );

create policy "agente cria interacoes nos proprios atendimentos"
  on interacoes for insert with check (
    exists (
      select 1 from atendimentos a
      where a.id = interacoes.atendimento_id and a.agente_id = auth.uid()
    )
  );

-- Auditoria: cada agente só consulta os eventos dos próprios atendimentos.
create policy "agente ve auditoria dos proprios atendimentos"
  on auditoria_linha for select using (agente_id = auth.uid());
-- (inserção em auditoria_linha só acontece via trigger, não precisa de policy de insert para o cliente)

-- ---------------------------------------------------------------------
-- 7) SUPERVISOR — agentes com agentes.is_admin = true enxergam e
--    gerenciam TODOS os atendimentos, interações e auditoria, de
--    qualquer agente e qualquer linha. As policies abaixo são
--    ADITIVAS às de cima (mesmo comando = combinado com OR), então
--    o agente comum continua restrito aos próprios chamados.
-- ---------------------------------------------------------------------

-- security definer evita recursão de RLS ao consultar "agentes" de
-- dentro da própria policy de "agentes" (e é mais rápido: 1 lookup).
create or replace function public.is_admin()
returns boolean
language sql
security definer
stable
as $$
  select coalesce((select is_admin from agentes where id = auth.uid()), false);
$$;

create policy "supervisor ve todos os atendimentos"
  on atendimentos for select using (public.is_admin());

create policy "supervisor atualiza qualquer atendimento"
  on atendimentos for update using (public.is_admin());

create policy "supervisor ve todas as interacoes"
  on interacoes for select using (public.is_admin());

create policy "supervisor cria interacoes em qualquer atendimento"
  on interacoes for insert with check (public.is_admin());

create policy "supervisor ve toda a auditoria"
  on auditoria_linha for select using (public.is_admin());

-- Para promover um agente a Supervisor, depois de ele já ter feito
-- login ao menos uma vez (o que cria a linha em "agentes"), rode:
--   update agentes set is_admin = true where email = 'supervisor@empresa.com';

-- =====================================================================
-- FIM DO SCRIPT. Depois de rodar, crie os agentes em
-- Authentication > Users > Add user (e-mail + senha) no painel Supabase.
-- =====================================================================
