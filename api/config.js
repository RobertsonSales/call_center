// /api/config — função serverless do Vercel.
// Lê as credenciais do Supabase das variáveis de ambiente do projeto
// (Vercel → Project Settings → Environment Variables) e as devolve ao
// front-end em tempo de execução, para que a chave nunca precise ficar
// escrita no código-fonte (index.html) nem no repositório do GitHub.
//
// A chave devolvida é a "anon public key" do Supabase — ela é feita
// para ser usada no navegador; quem realmente controla o que cada
// agente pode ler/gravar são as políticas de RLS no banco (schema.sql).
// Mantê-la como variável de ambiente permite trocá-la/rotacioná-la sem
// alterar ou reenviar código.

export default function handler(req, res) {
  const url = process.env.SUPABASE_URL;
  const anonKey = process.env.SUPABASE_ANON_KEY;

  if (!url || !anonKey) {
    res.status(500).json({ error: 'SUPABASE_URL ou SUPABASE_ANON_KEY não configuradas no Vercel.' });
    return;
  }

  // não deixa CDNs/proxies guardarem essa resposta em cache
  res.setHeader('Cache-Control', 'no-store');
  res.status(200).json({ url, anonKey });
}
