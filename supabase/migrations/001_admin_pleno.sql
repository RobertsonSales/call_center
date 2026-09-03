-- ============================================================================
-- Migração 001 — Arquitetura de Permissões: Administrador Pleno
-- Grupo Labmedic — Sistema de Atendimento Técnico Interno
--
-- Referência: documento "Arquitetura de Permissões — Administrador Pleno"
-- Aditiva: não remove nem quebra nada do que já existe (agentes, RLS atuais).
-- ============================================================================

begin;

-- ----------------------------------------------------------------------------
-- 1. Nova coluna de papel (substitui o uso isolado de is_admin)
-- ----------------------------------------------------------------------------
alter table agentes
  add column if not exists papel text not null default 'tecnico'
  check (papel in ('tecnico', 'supervisor', 'admin_pleno'));

-- migração dos dados hoje existentes a partir do campo is_admin, se ele existir
-- (ajuste o nome da coluna abaixo caso o campo atual tenha outro nome)
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_name = 'agentes' and column_name = 'is_admin'
  ) then
    update agentes set papel = 'supervisor' where is_admin = true  and papel = 'tecnico';
    update agentes set papel = 'tecnico'    where is_admin = false and papel = 'tecnico';
  end if;
end $$;

-- ----------------------------------------------------------------------------
-- 2. Salvaguarda do "último administrador" — trava no próprio banco
--    Vale para qualquer caminho de alteração (tela, autoexclusão, chamada
--    direta ao banco), pois roda dentro do PostgreSQL, não no código da app.
-- ----------------------------------------------------------------------------
create or replace function fn_impedir_ultimo_admin()
returns trigger as $$
begin
  -- só verifica quando a linha alterada ESTÁ deixando de ser admin pleno ativo
  if old.papel = 'admin_pleno' and old.ativo = true
     and (new.papel <> 'admin_pleno' or new.ativo = false) then
    if (select count(*) from agentes
        where papel = 'admin_pleno' and ativo = true and id <> old.id) = 0 then
      raise exception
        'Não é possível concluir: pelo menos um Administrador Pleno precisa permanecer ativo.';
    end if;
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_impedir_ultimo_admin on agentes;
create trigger trg_impedir_ultimo_admin
  before update on agentes
  for each row execute function fn_impedir_ultimo_admin();

-- mesma trava também para exclusão física da linha (se algum dia for permitida)
create or replace function fn_impedir_ultimo_admin_delete()
returns trigger as $$
begin
  if old.papel = 'admin_pleno' and old.ativo = true then
    if (select count(*) from agentes
        where papel = 'admin_pleno' and ativo = true and id <> old.id) = 0 then
      raise exception
        'Não é possível excluir: pelo menos um Administrador Pleno precisa permanecer ativo.';
    end if;
  end if;
  return old;
end;
$$ language plpgsql;

drop trigger if exists trg_impedir_ultimo_admin_delete on agentes;
create trigger trg_impedir_ultimo_admin_delete
  before delete on agentes
  for each row execute function fn_impedir_ultimo_admin_delete();

-- ----------------------------------------------------------------------------
-- 3. Log de auditoria de mudança de papel
-- ----------------------------------------------------------------------------
create table if not exists agentes_eventos (
  id uuid primary key default gen_random_uuid(),
  agente_alterado_id uuid not null references agentes(id),
  agente_executor_id uuid references agentes(id),
  papel_anterior text,
  papel_novo text,
  criado_em timestamptz not null default now()
);

create or replace function fn_registrar_evento_papel()
returns trigger as $$
begin
  if new.papel is distinct from old.papel then
    insert into agentes_eventos (agente_alterado_id, agente_executor_id, papel_anterior, papel_novo)
    values (new.id, auth.uid(), old.papel, new.papel);
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists trg_registrar_evento_papel on agentes;
create trigger trg_registrar_evento_papel
  after update on agentes
  for each row execute function fn_registrar_evento_papel();

alter table agentes_eventos enable row level security;

drop policy if exists "admin_pleno_le_eventos" on agentes_eventos;
create policy "admin_pleno_le_eventos" on agentes_eventos
  for select using (
    exists (select 1 from agentes a where a.id = auth.uid() and a.papel = 'admin_pleno')
  );

-- ----------------------------------------------------------------------------
-- 4. Ajuste das políticas de segurança (RLS) da tabela agentes
--    Ajuste os nomes das policies abaixo caso já existam políticas com outros
--    nomes cobrindo o mesmo escopo — o objetivo é o comportamento, não o nome.
-- ----------------------------------------------------------------------------

-- leitura: qualquer agente autenticado pode ver a lista (já era o padrão atual)
drop policy if exists "agentes_leitura" on agentes;
create policy "agentes_leitura" on agentes
  for select using (auth.role() = 'authenticated');

-- atualização de papel para/de 'admin_pleno': só quem já é admin_pleno
drop policy if exists "agentes_update_admin_pleno" on agentes;
create policy "agentes_update_admin_pleno" on agentes
  for update using (
    exists (select 1 from agentes a where a.id = auth.uid() and a.papel = 'admin_pleno')
  )
  with check (true);

-- atualização entre 'tecnico' e 'supervisor': supervisor ou admin_pleno
-- (mantém o comportamento já existente hoje para o Supervisor)
drop policy if exists "agentes_update_supervisor" on agentes;
create policy "agentes_update_supervisor" on agentes
  for update using (
    exists (
      select 1 from agentes a where a.id = auth.uid()
      and a.papel in ('supervisor', 'admin_pleno')
    )
    and papel in ('tecnico', 'supervisor')
  )
  with check (papel in ('tecnico', 'supervisor'));

commit;

-- ============================================================================
-- Após aplicar esta migração:
-- 1) Promover manualmente ao menos um usuário existente para 'admin_pleno':
--      update agentes set papel = 'admin_pleno' where email = 'seu-email@labmedic...';
-- 2) Testar a salvaguarda: tentar rebaixar esse único admin_pleno e confirmar
--    que o banco recusa com a mensagem de erro esperada.
-- ============================================================================

