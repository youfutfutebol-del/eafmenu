// api/config.js
// Função serverless da Vercel (roda mesmo sem build step — qualquer arquivo
// dentro de /api vira automaticamente uma função).
//
// Lê as variáveis de ambiente configuradas no dashboard da Vercel:
// Project Settings > Environment Variables
//   NEXT_PUBLIC_SUPABASE_URL       (pública, pode ser exposta no browser)
//   NEXT_PUBLIC_SUPABASE_ANON_KEY  (pública, respeita RLS sempre)
//
// A SUPABASE_SECRET_KEY (service_role) NÃO é lida nem devolvida aqui —
// ela ignora o RLS por completo e só deve ser usada dentro de funções
// serverless que fazem operações administrativas (ex: criar um tenant novo).
// Nenhuma função deste tipo existe ainda neste projeto.
//
// Nota: a anon key SEMPRE fica visível no navegador de quem usa o painel,
// não importa onde ela seja guardada — isso é esperado e seguro, porque
// quem protege seus dados de verdade é o RLS já configurado no banco.

export default function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store');
  res.status(200).json({
    url: process.env.NEXT_PUBLIC_SUPABASE_URL,
    anonKey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  });
}
