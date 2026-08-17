# Central de Atendimento Técnico via WhatsApp — Guia de Implantação

Aplicação de página única (`index.html`) para um call center que atende
clientes por WhatsApp usando links `wa.me` (sem Cloud API/Meta Business),
com login de agentes, protocolo automático, histórico de procedimentos,
transferência entre especialistas e auditoria — tudo gravado no Supabase.

## Arquivos
- `index.html` — aplicação completa (HTML + CSS + JS, sem build).
- `schema.sql` — script único para criar todo o banco no Supabase.
- `api/config.js` — função serverless do Vercel que entrega a URL e a
  chave anon do Supabase ao front-end a partir de variáveis de
  ambiente (a chave não fica escrita em `index.html` nem no repositório).
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
6. Vá em **Project Settings → API** e copie:
   - **Project URL**
   - **anon public key**

   > A chave `anon` é segura para expor no front-end: o controle de
   > acesso real é feito pelas políticas de RLS no banco, não pela chave.

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
   cadastre duas variáveis:

   | Name                 | Value                                   |
   |----------------------|------------------------------------------|
   | `SUPABASE_URL`       | a Project URL copiada no passo 1.6       |
   | `SUPABASE_ANON_KEY`  | a anon public key copiada no passo 1.6   |

   Marque os três ambientes (Production, Preview, Development).
4. O projeto é um site estático com uma função serverless em `api/`
   (padrão suportado nativamente pelo Vercel) — não é preciso
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

## 6) Pontos de atenção e possíveis evoluções

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
