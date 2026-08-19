// /api/agentes.js — função serverless do Vercel para criação de
// contas de agente (login/senha).
//
// Por que isso precisa ser uma função de servidor e não uma chamada
// direta do navegador: criar um USUÁRIO DE AUTENTICAÇÃO (não uma
// linha de tabela comum) exige a "service_role key" do Supabase —
// uma chave com poderes administrativos totais, que ignora RLS. Ela
// NUNCA pode ser enviada ao navegador (equivale a dar a senha mestra
// do banco). Por isso ela mora só aqui, lida de uma variável de
// ambiente do servidor, e esta função checa, a cada chamada, se quem
// está pedindo (via token do próprio login) é realmente um supervisor
// antes de fazer qualquer alteração.
//
// IMPORTANTE: esta função NUNCA exclui agentes — só cria. A exclusão
// foi deliberadamente removida de toda a aplicação (front-end e
// back-end) para preservar o histórico de atendimentos vinculado a
// cada agente, para fins de auditoria. A única forma de desativar um
// acesso é "Inativar" (agentes.ativo = false), que mantém tudo
// intacto e reversível.
//
// Variáveis de ambiente necessárias (Vercel → Environment Variables):
//   SUPABASE_URL               (já existente)
//   SUPABASE_SERVICE_ROLE_KEY  (nova — Project Settings → API → service_role)

import { createClient } from '@supabase/supabase-js';

async function getSolicitanteAdmin(req, supabaseAdmin){
  const authHeader = req.headers['authorization'] || '';
  const token = authHeader.replace(/^Bearer\s+/i, '');
  if(!token) return null;

  const { data: userData, error: userErr } = await supabaseAdmin.auth.getUser(token);
  if(userErr || !userData?.user) return null;

  const { data: agente, error: agErr } = await supabaseAdmin
    .from('agentes')
    .select('id, is_admin, ativo')
    .eq('id', userData.user.id)
    .single();

  if(agErr || !agente || !agente.is_admin || agente.ativo === false) return null;
  return agente;
}

export default async function handler(req, res){
  const url = process.env.SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if(!url || !serviceKey){
    res.status(500).json({ error: 'SUPABASE_URL ou SUPABASE_SERVICE_ROLE_KEY não configuradas no Vercel.' });
    return;
  }

  const supabaseAdmin = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false }
  });

  const solicitante = await getSolicitanteAdmin(req, supabaseAdmin);
  if(!solicitante){
    res.status(403).json({ error: 'Apenas supervisores autenticados podem gerenciar agentes.' });
    return;
  }

  // ---------------- CRIAR AGENTE ----------------
  if(req.method === 'POST'){
    const { nome, email, senha } = req.body || {};
    if(!nome || !email || !senha){
      res.status(400).json({ error: 'Informe nome, e-mail e senha.' });
      return;
    }
    if(String(senha).length < 6){
      res.status(400).json({ error: 'A senha precisa ter ao menos 6 caracteres.' });
      return;
    }

    const { data, error } = await supabaseAdmin.auth.admin.createUser({
      email: String(email).trim(),
      password: String(senha),
      email_confirm: true, // já vem confirmado — evita depender de e-mail de verificação
      user_metadata: { nome: String(nome).trim() }
    });

    if(error){
      res.status(400).json({ error: 'Não foi possível criar o agente: ' + error.message });
      return;
    }

    // o trigger handle_new_agente já cria a linha em "agentes" automaticamente
    res.status(200).json({ ok: true, id: data.user.id });
    return;
  }

  // Exclusão de agentes é permanentemente indisponível nesta rota —
  // inclusive para chamadas diretas à API, não só pela interface.
  res.status(405).json({ error: 'Método não suportado. A exclusão de agentes foi desativada — use "Inativar" para preservar o histórico de auditoria.' });
}
