// Fundação compartilhada para disponibilidade de recursos por plano.
// A autoridade permanece no banco; cada abertura revalida recursos_restaurante_atual().
(function () {
  'use strict';

  let consultaEmAndamento = null;
  let consultaSequencia = 0;
  let recursosAtuais = [];
  let modalFocoOrigem = null;
  let modalContexto = null;

  function normalizarRecurso(row) {
    return {
      restauranteId: row?.restaurante_id || null,
      restaurantePausado: row?.restaurante_pausado === true,
      planoCodigo: String(row?.plano_codigo || ''),
      planoNome: String(row?.plano_nome || ''),
      recursoCodigo: String(row?.recurso_codigo || ''),
      recursoNome: String(row?.recurso_nome || ''),
      recursoDescricao: String(row?.recurso_descricao || ''),
      disponivel: row?.disponivel === true,
      origem: String(row?.origem || ''),
      decisaoIndividual: row?.decisao_individual == null ? null : String(row.decisao_individual),
      planosElegiveis: Array.isArray(row?.planos_elegiveis)
        ? row.planos_elegiveis.map(String).filter(Boolean)
        : []
    };
  }

  function erroIndisponibilidade(error, recursoCodigo) {
    return String(error?.code || '') === '42501'
      && String(error?.details || '') === String(recursoCodigo || '');
  }

  async function consultarAtualizado(botao) {
    if (consultaEmAndamento) return consultaEmAndamento;

    const sequencia = ++consultaSequencia;
    const estavaDesabilitado = Boolean(botao?.disabled);
    if (botao) {
      botao.disabled = true;
      botao.setAttribute('aria-busy', 'true');
    }

    consultaEmAndamento = (async () => {
      try {
        const { data, error } = await sb.rpc('recursos_restaurante_atual');
        if (sequencia !== consultaSequencia) return { status: 'obsoleta', recursos: [] };
        if (error) return { status: 'erro', error, recursos: [] };
        recursosAtuais = (data || []).map(normalizarRecurso);
        return { status: 'ok', recursos: recursosAtuais };
      } catch (error) {
        if (sequencia !== consultaSequencia) return { status: 'obsoleta', recursos: [] };
        return { status: 'erro', error, recursos: [] };
      } finally {
        if (botao?.isConnected) {
          botao.disabled = estavaDesabilitado;
          botao.removeAttribute('aria-busy');
        }
        if (sequencia === consultaSequencia) consultaEmAndamento = null;
      }
    })();

    return consultaEmAndamento;
  }

  async function verificar(recursoCodigo, botao) {
    const consulta = await consultarAtualizado(botao);
    if (consulta.status !== 'ok') return { status: 'erro', error: consulta.error || null, recurso: null };
    const recurso = consulta.recursos.find(item => item.recursoCodigo === recursoCodigo) || null;
    if (!recurso) return { status: 'indisponivel', recurso: null };
    return { status: recurso.disponivel ? 'disponivel' : 'indisponivel', recurso };
  }

  async function autorizar(recursoCodigo, origem, contexto = {}) {
    const resultado = await verificar(recursoCodigo, origem);
    if (typeof contexto.respostaAindaAtual === 'function' && !contexto.respostaAindaAtual()) {
      return { permitido: false, motivo: 'obsoleta', recurso: resultado.recurso || null, error: null };
    }
    if (resultado.status === 'erro') {
      return { permitido: false, motivo: 'erro', recurso: null, error: resultado.error || null };
    }
    if (resultado.status !== 'disponivel') {
      abrirModalIndisponivel(resultado.recurso || {
        recursoCodigo,
        recursoNome: contexto.nomeFallback || 'Recurso',
        planoCodigo: '',
        planoNome: '',
        origem: 'desconhecida',
        decisaoIndividual: null,
        planosElegiveis: []
      }, contexto.focoRetorno || origem, contexto);
      return { permitido: false, motivo: 'indisponivel', recurso: resultado.recurso || null, error: null };
    }
    return { permitido: true, motivo: 'disponivel', recurso: resultado.recurso, error: null };
  }

  function invalidarConsultas() {
    consultaSequencia++;
    consultaEmAndamento = null;
  }

  function marcarIndisponivel(recursoCodigo) {
    recursosAtuais = recursosAtuais.map(recurso => recurso.recursoCodigo === recursoCodigo
      ? { ...recurso, disponivel: false }
      : recurso);
  }

  function registrarNegativa(error, recursoCodigo) {
    if (!erroIndisponibilidade(error, recursoCodigo)) return false;
    marcarIndisponivel(recursoCodigo);
    invalidarConsultas();
    return true;
  }

  function listaPlanosTexto(planos) {
    if (planos.length === 1) return `Disponível no pacote ${planos[0]}.`;
    const ultimo = planos[planos.length - 1];
    return `Disponível nos pacotes ${planos.slice(0, -1).join(', ')} e ${ultimo}.`;
  }

  function abrirModalIndisponivel(recurso, origem, contexto) {
    const nome = recurso?.recursoNome || 'Recurso';
    const planos = recurso?.planosElegiveis || [];
    const planoAtual = recurso?.planoNome || recurso?.planoCodigo || '';
    modalFocoOrigem = origem || document.activeElement;
    modalContexto = { recurso, contexto: contexto || {} };

    document.getElementById('recursoIndisponivelTitulo').textContent = contexto?.tituloIndisponivel || `${nome} não disponível`;
    const origemNegativa = recurso?.origem || '';
    let mensagem = `${nome} não está disponível no momento.`;
    let mostrarElegiveis = false;
    if (origemNegativa === 'nao_incluido') {
      mensagem = planoAtual
        ? `O recurso ${nome} não está incluído no seu pacote ${planoAtual}.`
        : `O recurso ${nome} não está disponível no seu pacote atual.`;
      mostrarElegiveis = planos.length > 0;
    } else if (origemNegativa === 'excecao_bloqueada') {
      mensagem = `O acesso ao recurso ${nome} está desativado para este restaurante.`;
    } else if (origemNegativa === 'plano_inativo') {
      mensagem = 'O pacote atual do restaurante está temporariamente indisponível.';
    } else if (origemNegativa === 'recurso_inativo') {
      mensagem = `${nome} está temporariamente indisponível.`;
    }
    document.getElementById('recursoIndisponivelMensagem').textContent = mensagem;
    const elegiveis = document.getElementById('recursoIndisponivelElegiveis');
    elegiveis.textContent = mostrarElegiveis ? listaPlanosTexto(planos) : '';
    elegiveis.hidden = !mostrarElegiveis;
    document.getElementById('recursoIndisponivelModalBg').classList.add('show');
    requestAnimationFrame(() => document.getElementById('recursoIndisponivelContatoBtn')?.focus());
  }

  function fecharModalIndisponivel() {
    document.getElementById('recursoIndisponivelModalBg').classList.remove('show');
    const destino = modalFocoOrigem;
    modalFocoOrigem = null;
    modalContexto = null;
    if (destino?.isConnected && destino.getClientRects().length && !destino.disabled) destino.focus();
  }

  function contatarSobreRecurso() {
    const recurso = modalContexto?.recurso;
    const contexto = modalContexto?.contexto || {};
    const nome = recurso?.recursoNome || 'recurso';
    let mensagem = `Olá, gostaria de ativar o recurso ${nome} no EAF Menu.`;
    if (contexto.restauranteNome) mensagem += ` Restaurante: ${contexto.restauranteNome}.`;
    const plano = recurso?.planoNome || recurso?.planoCodigo;
    if (plano) mensagem += ` Pacote atual: ${plano}.`;
    abrirWhatsapp('5541984213488', mensagem);
  }

  window.RecursosPlanos = Object.freeze({
    consultarAtualizado,
    verificar,
    autorizar,
    erroIndisponibilidade,
    invalidarConsultas,
    marcarIndisponivel,
    registrarNegativa,
    abrirModalIndisponivel,
    fecharModalIndisponivel,
    contatarSobreRecurso
  });
  window.fecharModalRecursoIndisponivel = fecharModalIndisponivel;
  window.contatarRecursoIndisponivel = contatarSobreRecurso;
})();
