// /assets/js/whatsapp.js
// Helper compartilhado pra montar e abrir links do WhatsApp (wa.me) com numero e mensagem seguros.
// Usado pelo painel do restaurante, app do cliente e app do motoboy. Sem dependencias externas;
// so precisa estar incluido antes de qualquer botao que chame abrirWhatsapp/montarLinkWhatsapp.

function montarLinkWhatsapp(numero, mensagem) {
  const digitos = String(numero || '').replace(/\D/g, '');
  if (!digitos) return null;
  const numeroComPais = digitos.length <= 11 ? '55' + digitos : digitos;
  const texto = mensagem ? ('?text=' + encodeURIComponent(mensagem)) : '';
  return 'https://wa.me/' + numeroComPais + texto;
}

function abrirWhatsapp(numero, mensagem) {
  const link = montarLinkWhatsapp(numero, mensagem);
  if (!link) return false;
  window.open(link, '_blank', 'noopener');
  return true;
}
