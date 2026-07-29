// /assets/js/utils.js
// Funcoes utilitarias puras, extraidas do index.html (Etapa 2 da fragmentacao).
// Sem Supabase, sem query no banco, sem logica de negocio. Continuam globais (sem type=module).

  function capitalize(s) { return s.charAt(0).toUpperCase() + s.slice(1); }

  function normalizarTelefoneAcesso(valor) {
    return String(valor || '').replace(/\D/g, '');
  }

  function formatHoraCurta(d) {
    return d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
  }

  function formatarDuracao(min) {
    const h = Math.floor(min / 60);
    const m = min % 60;
    if (h > 0) return `${h}h${String(m).padStart(2, '0')}min`;
    return `${m}min`;
  }

  function formatMoeda(v) {
    return 'R$ ' + Number(v).toFixed(2).replace('.', ',');
  }

  function escapeHtml(value) {
    return String(value ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#039;');
  }

  function validarUrlSegura(value, { permitirRelativa = true } = {}) {
    const original = String(value ?? '').trim();
    if (!original) return null;
    if (permitirRelativa && original.startsWith('/') && !original.startsWith('//')) {
      try {
        const url = new URL(original, location.origin);
        return url.origin === location.origin ? url.pathname + url.search + url.hash : null;
      } catch (_) { return null; }
    }
    try {
      const url = new URL(original);
      return url.protocol === 'http:' || url.protocol === 'https:' ? url.href : null;
    } catch (_) { return null; }
  }

  function aplicarUrlSegura(elemento, atributo, value, opcoes) {
    const segura = validarUrlSegura(value, opcoes);
    if (!elemento || !['href', 'src'].includes(atributo)) return false;
    if (!segura) {
      elemento.removeAttribute(atributo);
      return false;
    }
    elemento.setAttribute(atributo, segura);
    return true;
  }

  function getProdutoPlaceholder(produto) {
    const nome = typeof produto === 'string' ? produto : produto?.nome;
    const letra = String(nome || 'P').trim().charAt(0).toUpperCase() || 'P';
    return `<div class="produto-placeholder">${escapeHtml(letra)}</div>`;
  }

  function formatMoedaRel(v) { return 'R$ ' + Number(v || 0).toFixed(2).replace('.', ','); }

  function formatData(iso) {
    return new Date(iso).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
  }

  function slugify(texto) {
    return (texto || '')
      .toLowerCase()
      .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/(^-|-$)/g, '');
  }

  function showToast(title, body) {
    const t = document.getElementById('toast');
    document.getElementById('toastTitle').textContent = title;
    document.getElementById('toastBody').textContent = body;
    t.classList.add('show');
    clearTimeout(t._timer);
    t._timer = setTimeout(() => t.classList.remove('show'), 3600);
  }
