// /assets/js/whatsapp.js
// Helper compartilhado para abrir links do WhatsApp com numero e mensagem seguros.

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
  window.open(link, '_blank');
  return true;
}
