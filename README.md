# Central de Atendimento Técnico via WhatsApp — Guia de Implantação

Aplicação de página única (`index.html`) para um call center que atende
clientes por WhatsApp usando links `wa.me` (sem Cloud API/Meta Business),
com login de agentes, protocolo automático, histórico de procedimentos,
transferência entre especialistas e auditoria — tudo gravado no Supabase.

## Arquivos
- `index.html` — aplicação completa (HTML + CSS + JS, sem build).
- `schema.sql` — script único para criar/atualizar todo o banco no Supabase.
- `package.json` — declara a dependência `@supabase/supabase-js` usada
  pela função serverless `api/agentes.js` (o Vercel instala sozinho).
- `api/config.js` — função serverless que entrega URL/chave anon do
  Supabase ao front-end a partir de variáveis de ambiente.
- `api/agentes.js` — função serverless que cria e exclui contas de
  agente usando a *service role key* (nunca exposta ao navegador),
  só executável por quem já está logado como Supervisor.
- `.env.example` — modelo das variáveis de ambiente, para testar localmente.
- `.gitignore` — garante que seu `.env` local nunca seja commitado.

---

## 1) Criar e configurar o projeto no Supabase

1. Acesse **supabase.com** → **New project**. Anote a senha do banco.
2. No menu lateral, vá em **SQL Editor** → **New query**.
3. Cole todo o conteúdo de `schema.sql` e clique em **Run**. Isso cria:
   - `agentes`, `linhas`, `atendimentos`, `interacoes`, `auditoria_linha`;
   - a geração automática de protocolo (`AT-YYYYMMDD-00001`);
   - os gatilhos que gravam a auditoria por linha sozinhos;
   - as políticas de RLS (só usuários autenticados leem/gravam).
4. Vá em **Authentication → Providers** e confirme que **Email** está
   habilitado (é o padrão).
5. Vá em **Authentication → Users → Add user** e cadastre um usuário
   para cada agente (e-mail + senha). O trigger do script já cria o
   perfil correspondente na tabela `agentes` automaticamente.
5.1. **Promover um Supervisor**: depois que a pessoa fizer login pelo
   menos uma vez (o que cria a linha dela em `agentes`), volte ao
   **SQL Editor** e rode, trocando o e-mail:
   ```sql
   update agentes set is_admin = true where email = 'supervisor@empresa.com';
   ```
   Um Supervisor enxerga e pode reatribuir **todos** os atendimentos,
   de todos os agentes e linhas (menu "Supervisão", visível só para
   quem tem `is_admin = true`) — os demais agentes continuam vendo
   apenas os próprios chamados.
6. Vá em **Project Settings → API** e copie três valores:
   - **Project URL**
   - **anon public key**
   - **service_role key** (na mesma tela, um pouco mais abaixo — vem
     marcada como "secret")

   > A chave `anon` é segura para expor no front-end: o controle de
   > acesso real é feito pelas políticas de RLS no banco, não pela chave.
   > **A `service_role key` é diferente: NUNCA deve chegar ao
   > navegador.** Ela ignora todas as políticas de RLS — é o
   > equivalente a uma senha mestra do banco. Ela só é usada dentro da
   > função `api/agentes.js`, que roda no servidor do Vercel, para
   > criar/excluir contas de agente. Guarde-a com o mesmo cuidado que
   > uma senha de administrador.

---

## 2) Configurar a aplicação (sem editar o código)

A URL e a chave do Supabase **não ficam escritas no `index.html`**. Elas
são lidas em tempo de execução pela função `api/config.js`, a partir de
variáveis de ambiente do próprio Vercel — então esse passo é feito no
painel do Vercel, não no código (veja o passo 4.3 abaixo). Guarde a
**Project URL** e a **anon public key** copiadas no passo anterior; você
vai colá-las lá.

---

## 3) Subir o código para o GitHub

```bash
mkdir central-atendimento && cd central-atendimento
# coloque aqui: index.html, schema.sql, README.md, .gitignore,
# .env.example e a pasta api/ (com config.js)
git init
git add .
git commit -m "Central de atendimento via WhatsApp"
git branch -M main
git remote add origin https://github.com/SEU-USUARIO/central-atendimento.git
git push -u origin main
```

(Ou crie o repositório pelo próprio site do GitHub e faça upload dos
arquivos pela interface, sem usar linha de comando — inclua também a
pasta `api/` com o `config.js` dentro dela.)

> O `.gitignore` já impede que um `.env` local seja enviado ao GitHub —
> as credenciais reais só existem no painel do Vercel (próximo passo).

---

## 4) Publicar no Vercel

1. Acesse **vercel.com** → **Add New → Project**.
2. Importe o repositório `central-atendimento` do GitHub.
3. **Antes de clicar em Deploy**, abra **Environment Variables** e
   cadastre três variáveis:

   | Name                         | Value                                        |
   |------------------------------|-----------------------------------------------|
   | `SUPABASE_URL`               | a Project URL copiada no passo 1.6             |
   | `SUPABASE_ANON_KEY`          | a anon public key copiada no passo 1.6         |
   | `SUPABASE_SERVICE_ROLE_KEY`  | a service_role key copiada no passo 1.6        |

   Marque os três ambientes (Production, Preview, Development).
4. Como agora existe um `package.json` com uma dependência
   (`@supabase/supabase-js`, usada só pela função `api/agentes.js`), o
   Vercel detecta e instala sozinho — continua não sendo preciso
   configurar build command nem output directory. Clique em **Deploy**.
5. Em alguns minutos você recebe uma URL pública, ex:
   `https://central-atendimento.vercel.app`. A página busca
   `/api/config` assim que carrega para obter as credenciais do
   Supabase — se as variáveis de ambiente estiverem certas, o botão
   **Entrar** habilita sozinho.
6. Compartilhe essa URL com os agentes. Cada um faz login com o e-mail
   e senha cadastrados no passo 1.5.

Se depois for preciso trocar de projeto Supabase ou rotacionar a chave,
basta atualizar as duas variáveis em **Project Settings → Environment
Variables** no Vercel e clicar em **Redeploy** — sem tocar no código.

---

## 5) Como o fluxo funciona no dia a dia

1. **Novo Atendimento** → o agente escolhe a linha que recebeu o
   contato, preenche os dados do cliente e clica em **Gerar protocolo**.
   O sistema cria o registro no Supabase, gera o protocolo
   (`AT-20260817-00001`) e abre automaticamente o WhatsApp (Web ou app)
   com a mensagem inicial pronta para envio com um clique.
2. **Atendimentos Ativos** → lista os chamados em aberto/andamento. Ao
   clicar em um protocolo, o agente vê o histórico e pode escrever um
   novo procedimento técnico, salvando-o e opcionalmente abrindo o
   WhatsApp já com aquele texto pronto para enviar ao cliente.
3. **Transferir** → dentro do detalhe do protocolo, o agente informa o
   WhatsApp de outro especialista; o sistema monta um resumo com todo o
   histórico do atendimento e abre o WhatsApp para esse novo número já
   com o texto pronto — o especialista recebe o contexto completo sem
   precisar reperguntar nada ao cliente.
4. **Histórico & Auditoria** → filtra todos os atendimentos por período,
   número de protocolo, linha de origem ou status. Cada linha de
   WhatsApp que gera chamados fica com seu próprio registro de auditoria
   (tabela `auditoria_linha`), preenchido automaticamente pelo banco.
5. **Reenvio** → a partir do histórico, é possível reabrir qualquer
   protocolo antigo e reenviar o resumo completo para outro WhatsApp,
   se for preciso retomar um atendimento já encerrado.

---

## 6) Funcionalidades adicionadas: CRUD de agentes/linhas e exportação

**Linhas de WhatsApp** (menu "Linhas WhatsApp", qualquer agente):
- Criar, editar (nome/número), ativar/inativar e excluir.
- A exclusão só é permitida se a linha nunca recebeu atendimentos (o
  banco protege isso via chave estrangeira); se houver histórico
  vinculado, a aplicação orienta a usar "Inativar" em vez de excluir —
  isso preserva a auditoria.

**Agentes** (menu "Agentes", só para Supervisor):
- Lista todos os agentes com papel (Agente/Supervisor) e status
  (Ativo/Inativo).
- Permite promover/remover o papel de Supervisor e ativar/inativar um
  acesso, direto pela interface.
- **Criar uma conta nova continua sendo feito no painel do Supabase**
  (Authentication → Users → Add user) — por segurança, a aplicação não
  cria contas de autenticação pelo navegador. Assim que a pessoa é
  criada lá, o perfil aparece automaticamente nesta tela.
- Um agente **inativado** tem a sessão encerrada automaticamente no
  próximo login (a aplicação verifica `agentes.ativo` e desloga se for
  `false`). Um supervisor não consegue inativar nem remover o próprio
  papel de supervisor pela tela (trava tanto na interface quanto na
  policy do banco — veja a seção 7 do `schema.sql`).

**Exportação em PDF e Excel**:
- Nas telas **Histórico** e **Supervisão**, os botões "⬇ PDF" e
  "⬇ Excel" exportam exatamente os resultados filtrados na tela — filtre
  por período/protocolo/linha/agente/status antes de exportar.
- No detalhe de qualquer protocolo (clique numa linha da tabela), o
  botão "⬇ Exportar PDF" gera um PDF só daquele atendimento, com os
  dados do chamado e o histórico completo de procedimentos — útil para
  anexar a um e-mail ou arquivar fora do sistema.
- A geração roda toda no navegador (bibliotecas jsPDF e SheetJS via
  CDN) — nenhum dado é enviado a um servidor externo para gerar os
  arquivos.

> **Importante — se você já rodou o `schema.sql` antes**: esta versão
> adicionou uma policy nova (`supervisor gerencia perfis de agentes`)
> necessária para os botões de ativar/inativar e promover/remover
> supervisor funcionarem. Cole o `schema.sql` atualizado no SQL Editor
> e rode de novo — como todo o script agora é idempotente (`drop
> policy if exists` antes de cada `create policy`), isso não duplica
> nada, só adiciona a policy que faltava.

---

## 7) Identidade visual, sessão, tema, mobile, máscara e duração

**Identidade**: título e cabeçalhos agora exibem "GRUPO LABMEDIC –
Sistema de Atendimento Técnico Interno".

**Logout automático ao fechar a aba**: a sessão do Supabase passou a
usar `sessionStorage` em vez de `localStorage` — o próprio navegador
apaga esse armazenamento quando a aba é fechada, então a pessoa
precisa logar de novo na próxima vez que abrir a aplicação. Efeito
colateral esperado: abrir a aplicação em duas abas ao mesmo tempo exige
login em cada uma (elas não compartilham sessão) — isso é intencional
para este modelo de "logout ao fechar".

**Tema claro/escuro**: botão flutuante (ícone de lua/sol) no canto
superior direito, em qualquer tela. A escolha fica salva no navegador
(`localStorage`) e, na primeira visita, a aplicação usa o tema que o
sistema operacional do agente já está configurado para usar.

**Responsividade mobile**: em telas estreitas, a barra lateral vira um
menu hambúrguer deslizante, e as tabelas ganham rolagem horizontal em
vez de espremer as colunas.

**Máscara de celular pt-BR**: os campos de WhatsApp do cliente e de
número de linha mostram um prefixo fixo `+55` e formatam o restante
como `(DD) 9XXXX-XXXX` enquanto o agente digita. Internamente o número
é sempre salvo completo, com o DDI — o `+55` some do campo, mas não do
dado gravado no banco. (Os dois únicos pontos que ainda usam uma
caixinha de texto simples em vez da máscara são a edição de linha via
"Editar" e a transferência de atendimento, que pedem o número por uma
janela de diálogo do navegador — funcionam normalmente, só sem a
formatação visual.)

**Horário de início/fim e duração**: todo atendimento já tinha o
horário de criação (início). Agora, ao clicar em "Encerrar
atendimento", o horário atual é gravado como fim
(`atendimentos.encerrado_em`), e a aplicação calcula a duração
automaticamente (e mostra "em andamento" enquanto não há horário de
fim) — visível nas tabelas de Histórico/Supervisão, no detalhe do
protocolo e em todas as exportações PDF/Excel.

**CRUD completo de Agentes com criação/exclusão pelo navegador**: além
de ativar/inativar e promover/remover supervisor (já existentes), o
menu Agentes agora tem um formulário para **criar** um agente novo
(nome, e-mail, senha) e um botão para **excluir** um agente —
substituindo a necessidade de ir ao painel do Supabase para essas duas
ações. Por trás dos panos, isso passa pela função `api/agentes.js`, que
roda no servidor (nunca no navegador) e confere que quem está pedindo
é mesmo um Supervisor logado antes de tocar em qualquer conta.

> **Se você já tinha rodado o schema antes desta versão**: além de
> rodar o `schema.sql` atualizado (para a coluna `encerrado_em`), é
> necessário também configurar a nova variável de ambiente
> `SUPABASE_SERVICE_ROLE_KEY` no Vercel (passo 4 acima) e fazer um novo
> deploy — sem ela, criar/excluir agentes pela aplicação não funciona
> (as demais funções continuam normais).

---

## 8) Pontos de atenção e possíveis evoluções

- **RLS por agente + Supervisor**: cada agente comum só vê, cria e
  atualiza os próprios atendimentos (`agente_id = auth.uid()`) —
  inclusive no Painel, em Atendimentos Ativos e no Histórico/Auditoria.
  Quem tem `agentes.is_admin = true` é Supervisor: enxerga o menu
  "Supervisão" (todos os protocolos, de todos os agentes e linhas, com
  filtro por agente) e pode reatribuir qualquer atendimento a outro
  agente — tudo isso reforçado pelas policies do banco (função
  `is_admin()` em `schema.sql`), não só escondido na interface.
- **Chave do Supabase fora do código**: `index.html` não contém mais a
  URL nem a chave `anon` — elas são buscadas em `/api/config`, uma
  função serverless que as lê das variáveis de ambiente do Vercel. Isso
  não torna a chave "secreta" (ela ainda chega ao navegador do agente,
  como em qualquer app que fala direto com o Supabase), mas evita que
  ela fique fixa no repositório e permite trocá-la sem reenviar código.
- **Números de telefone**: o app espera o formato E.164 sem o `+`
  (ex: `5521988887777`). Um número em formato errado ainda gera um link
  `wa.me`, mas ele pode não abrir a conversa correta.
- **wa.me e limite de caracteres**: mensagens muito longas (resumos de
  transferência com muitas interações) podem ultrapassar o limite
  prático da URL do WhatsApp em alguns navegadores. Se isso acontecer
  com atendimentos muito extensos, considere resumir automaticamente as
  interações mais antigas antes de montar o link.
- **Backup/exportação em massa**: hoje a exportação é feita
  protocolo a protocolo (reenvio via WhatsApp). Se precisar de
  exportação em lote (CSV/Excel) para auditoria externa, isso pode ser
  adicionado lendo as tabelas `atendimentos`/`interacoes` filtradas por
  período, direto do Supabase.
