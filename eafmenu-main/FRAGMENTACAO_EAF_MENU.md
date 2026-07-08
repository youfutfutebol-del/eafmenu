# FRAGMENTACAO_EAF_MENU.md

> Documento de continuidade. Cole este arquivo inteiro no início de um novo chat para o Claude continuar exatamente de onde este projeto parou — arquitetura, decisões de segurança já aplicadas, e progresso da fragmentação do `index.html` do painel admin.

---

# Projeto

**Nome:** EAF Menu (produto da EAF Flow)

**Objetivo do sistema:** SaaS multi-restaurante para delivery próprio — cardápio digital, pedidos em tempo real, painel administrativo, app do cliente (PWA) e app do motoboy (PWA). Foco inicial: delivery próprio, não marketplace.

**Stack:**
- HTML puro
- CSS puro
- JavaScript puro (sem framework, sem build step)
- Supabase (Postgres + Auth + Realtime + Storage + RLS)
- GitHub
- Vercel (deploy + `/api/config` server function pra servir `SUPABASE_URL`/`SUPABASE_ANON_KEY`)
- PWA (manifest + service worker) em `admin/`, `cliente/` e `motoboy/`

**Decisão estratégica fixada:** NÃO migrar para React, Vite, Next, TypeScript ou qualquer framework, sem pedido explícito do dono do projeto. Simplicidade é requisito de negócio (o dono precisa entender, manter e corrigir sozinho).

**Arquitetura atual:**
```
/
├── admin/ (ou index.html na raiz — ver nota abaixo)
├── api/
├── cliente/
├── motoboy/
├── icons/
├── index.html
├── manifest.json
└── sw.js
```

> **Nota importante de nomenclatura:** o painel do restaurante é servido pelo `index.html` da **raiz** do projeto (não existe uma pasta `admin/index.html` separada — isso foi confirmado durante a conversa: o usuário inicialmente achou que `index.html` da raiz era outra coisa, depois confirmou que É o painel admin). O super admin/plataforma NÃO tem uma tela própria neste repositório — a gestão de restaurante+dono é feita via RPC direta no banco (`criar_restaurante_com_dono`), chamada por quem tem acesso a `admins_plataforma`.

---

# Funcionalidades do sistema

## Painel do restaurante (`index.html` da raiz)
- Login por telefone/e-mail + senha (Supabase Auth, com RPC `resolver_email_login` pra mapear telefone/e-mail → e-mail interno)
- Primeiro acesso obrigatório troca de senha provisória
- Monitor de pedidos em tempo real (Realtime do Supabase)
- Pedido manual (lançado pelo atendente/balcão)
- Caixa (abertura, fechamento, extrato, despesas)
- Relatório Financeiro (só `dono`, ver seção própria)
- Produtos (com tamanhos e combinação de sabores, tipo pizza meio a meio)
- Categorias
- Grupos de tamanho
- Clientes (cadastro automático via pedidos)
- Entregadores/Motoboys (cadastro, ativar/desativar, redefinir senha)
- Gestão de Equipe (dono/gerente/atendente — criar, mudar cargo, desativar, remover)
- Personalizar Marca (nome, slug, logo, cor, whatsapp, endereço, instagram, horário de funcionamento)
- Impressão de comanda (formato térmico 80mm, via janela popup)
- Som de alerta pra pedido novo (Web Audio API, beep sintetizado)
- Instalação como PWA

## App do cliente (`cliente/index.html`)
- Cardápio público por slug (`?r=slug`)
- Sessão anônima via Supabase Auth (`signInAnonymously`), sem senha/OTP
- Identificação por nome + telefone (RPC `vincular_cliente_por_telefone`)
- Carrinho, seleção de tamanho e sabores (múltiplos sabores = preço médio)
- Checkout em 4 passos: identificação → entrega/retirada → pagamento → revisão
- Endereço de entrega (com busca de CEP via ViaCEP)
- Acompanhamento de pedido em tempo real (Realtime, com som de notificação)
- Status da loja (aberto/fechado) calculado a partir de `horarios_semana`
- Instalação como PWA

## App do motoboy (`motoboy/index.html`)
- Login por telefone + senha
- Visualização de pedidos atribuídos
- Atualização de status de entrega
- Bloqueio de acesso: só usuários com `role = 'motoboy'` entram; outros roles são barrados na tela do painel admin com mensagem "Use o app de entregas"

## Financeiro/Caixa
- Abertura de caixa (fundo de troco)
- Fechamento de caixa (conferência de dinheiro esperado vs. contado, com diferença calculada)
- Extrato de movimentações (entradas automáticas de pedidos pagos + despesas manuais)
- Histórico de fechamentos

## Produtos
- Preço único ou por grupo de tamanho
- Grupo de tamanho com `max_sabores` (1 = sem combinação; >1 = tipo pizza meio a meio, preço final = média entre os sabores escolhidos)
- Upload de imagem (Supabase Storage, bucket `imagens`)
- Ativar/ocultar produto

## Categorias
- CRUD simples, com ordem de exibição
- Bloqueio de exclusão se tiver produto vinculado

## Equipe
- Cargos: `dono`, `gerente`, `atendente`, `motoboy` (motoboy gerenciado na tela separada de Entregadores)
- Criação via RPC `criar_usuario_equipe` (cria conta de auth + usuário, com senha provisória)
- Gerente não pode criar/promover outro gerente ou dono (regra também no banco)
- Redefinir senha via RPC `redefinir_senha_usuario`
- Remover membro via RPC `remover_usuario_equipe`

## Marca
- Identidade visual do cardápio público: nome, slug, logo, cor de destaque, whatsapp, endereço, instagram, horário de funcionamento por dia da semana

## Relatórios
- RPC `relatorio_financeiro_v1(p_data_inicio, p_data_fim)` — só `dono` acessa (bloqueio dentro da própria função)
- Retorna: hoje, últimos 7 dias, mês corrente (cada um com faturamento/pedidos/ticket médio), divisão por forma de pagamento, divisão por tipo (entrega/retirada), top 5 produtos do mês, e bloco opcional de período personalizado com o mesmo detalhamento
- Considera só pedidos com `status in ('entregue','retirado')`
- Usa o mesmo conceito de "dia comercial" (corte às 7h) já usado no resto do sistema

## Pedido manual
- Lançado pelo atendente/dono direto no painel, pra pedido feito por telefone/balcão
- Busca cliente por telefone com debounce, pré-preenche nome/endereço se encontrar
- Mesma lógica de itens/preço do cardápio do cliente

## Realtime
- Canal `pedidos-restaurante-{restauranteId}` no admin — dispara som + toast em INSERT, recarrega lista em qualquer mudança
- Canal `tracking-cliente-{clienteId}` no app do cliente — atualiza tela de "Meus pedidos" e toca som quando o status muda

---

# Decisões arquiteturais importantes

## O que foi decidido e por quê
- **Sem framework.** Decisão estratégica do dono do projeto — precisa entender/manter/dar deploy sozinho.
- **RLS é a linha de defesa real, não a UI.** Esconder botão no frontend nunca é tratado como proteção suficiente — toda vez que isso apareceu como opção, a solução adotada foi trancar no banco (RLS ou RPC com checagem de role).
- **RPCs `SECURITY DEFINER` para ações sensíveis** (criar restaurante+dono, criar/remover equipe, redefinir senha, relatório financeiro) — porque permitem checagem de permissão centralizada, e servem cálculos que não podem ser confiados ao cliente (ex: total do pedido).
- **View `restaurantes_publico`** — criada porque a tabela `restaurantes` tem colunas sensíveis (assinatura/billing) que não podem ser lidas por visitantes anônimos, mas o cardápio público precisa ler algumas colunas da mesma tabela sem autenticação.
- **Triggers no banco para validar/recalcular preço e total do pedido** — porque o cliente não pode ser a fonte de verdade de valores financeiros (subtotal, total, taxa de entrega, preço unitário do item).
- **Fragmentação do `index.html` em múltiplos arquivos `.js` globais (sem bundler, sem módulos)** — pra reduzir o tamanho do arquivo e organizar por domínio, mantendo 100% de compatibilidade com o jeito atual de rodar o projeto (scripts clássicos, sem build step).

## O que NÃO deve ser alterado
- Não usar `import`/`export`.
- Não usar `type="module"`.
- Não renomear nenhuma função durante a fragmentação.
- Não alterar lógica interna de nenhuma função durante a fragmentação (mudanças de lógica são tarefas separadas, com análise própria).
- Não migrar para framework.
- Não confiar em valores financeiros vindos do cliente (sempre validar/recalcular no banco).
- Não esconder um recurso sensível só na UI sem proteção equivalente no banco.

## Padrões que estamos seguindo
- **Scripts clássicos compartilham escopo léxico global.** `let`/`const` declarados no topo de uma tag `<script>` ficam visíveis para outras tags `<script>` na mesma página (não viram `window.x`, mas são visíveis diretamente). Isso é o que permite fragmentar em múltiplos arquivos `.js` carregados **antes** do script principal, mesmo quando essas funções extraídas dependem de variáveis (`sb`, `currentUser`, `restauranteId` etc.) que só são inicializadas dentro do script principal — porque as funções extraídas só são **chamadas** via clique/evento depois que a página inteira já carregou.
- **Ordem de carregamento dos scripts é sempre preservada e nunca embaralhada** entre etapas.
- **Todo bloco de função extraído é conferido com `grep`/`diff` antes de ser considerado concluído** — nunca "confiar que deu certo", sempre confirmar contagem exata (0 no arquivo de origem, 1 no arquivo novo) e que o `diff` estrutural do HTML mostra só a linha da tag `<script>` adicionada.
- **Cada etapa da fragmentação é isolada e testável antes de prosseguir pra próxima.**

---

# Fragmentação do index.html

Arquivo de origem: `index.html` (raiz, painel admin). Tamanho original: ~146.000 caracteres. Tamanho atual (após Etapa 9): ~81.000 caracteres (estimativa, pode variar conforme novos commits e etapas de fragmentação).

## Etapa 1
**Arquivo criado:** `/assets/css/painel.css`
**O que mudou:** todo o conteúdo do bloco `<style>...</style>` do `index.html` foi movido pra esse arquivo. No `index.html`, o bloco `<style>` foi substituído por `<link rel="stylesheet" href="/assets/css/painel.css">`.
**Observação:** o único `<style>` que continua dentro do `index.html` é intencional — está dentro de uma template string JavaScript, na função `imprimirComanda()`, gerando o CSS da comanda térmica impressa. Não deve ser tocado.

## Etapa 2
**Arquivo criado:** `/assets/js/utils.js`
**Funções movidas:** `capitalize`, `formatHoraCurta`, `formatarDuracao`, `formatMoeda`, `formatMoedaRel`, `formatData`, `slugify`, `showToast`

## Etapa 3
**Arquivo criado:** `/assets/js/auth.js`
**Funções movidas:** `fazerLogin`, `setLoginMsg`, `abrirEsqueciSenha`, `fecharEsqueciSenha`, `enviarRecuperacaoSenha`, `mostrarTelaNovaSenhaRecuperacao`, `salvarNovaSenhaRecuperacao`, `abrirTrocarMinhaSenha`, `fecharTrocarMinhaSenha`, `submitTrocarMinhaSenha`, `logout`, `salvarSenhaPrimeiroAcesso`

## Etapa 4
**Arquivo criado:** `/assets/js/pedidos-utils.js`
**Funções movidas:** `timeAgo`, `codigoPedido`, `setFiltroPedidos`, `renderOrders`

## Etapa 5
**Arquivo criado:** `/assets/js/pedidos.js`
**Funções movidas:** `loadPedidos`, `subscribeRealtime`, `advanceStatus`, `atribuirMotoboy`, `marcarPago`, `imprimirComanda`, `beep`, `testAlert`

## Etapa 6
**Arquivo criado:** `/assets/js/produtos-categorias.js`
**Funções movidas:** `loadCategorias`, `loadCategoriasAdmin`, `fillCategoriaSelect`, `openCategoria`, `closeCategoria`, `submitCategoria`, `deleteCategoria`, `loadGruposTamanho`, `fillGrupoTamanhoSelect`, `loadProdutosAdmin`, `renderProdutosTable`, `toggleProdutoAtivo`, `setTipoPreco`, `onGrupoTamanhoChange`, `addNovoTamanhoRow`, `removeNovoTamanhoRow`, `atualizarNovoTamanho`, `renderNovosTamanhosRows`, `renderCamposPreco`, `openProduto`, `editProduto`, `closeProduto`, `submitProduto`, `uploadImagem`, `onImagemProdutoSelecionada`
**Observação:** `loadProdutos()` (minúsculo, sem "Admin") **não** foi movida — ela alimenta o dropdown do pedido manual, não a tela de gestão de produtos, e permanece no script principal.

## Etapa 7
**Arquivo criado:** `/assets/js/clientes-entregadores.js`
**Funções movidas:** `loadClientes`, `renderClientesTable`, `openClienteEdit`, `closeClienteEdit`, `submitClienteEdit`, `loadEntregadores`, `renderEntregadoresTable`, `openEntregador`, `closeEntregador`, `submitEntregador`, `toggleEntregadorAtivo`, `removerEntregador`, `abrirResetSenhaEntregador`, `redefinirSenhaEntregador`

## Etapa 8
**Arquivo criado:** `/assets/js/financeiro-caixa.js`
**Funções movidas:** `periodoInicio`, `loadMovimentacoes`, `setPeriodo`, `renderExtrato`, `openDespesa`, `closeDespesa`, `submitDespesa`, `loadCaixaAtual`, `calcularMovimentoDinheiro`, `renderCaixaStatus`, `openAbrirCaixa`, `closeAbrirCaixa`, `submitAbrirCaixa`, `openFecharCaixa`, `closeFecharCaixa`, `atualizarDiferencaFechamento`, `submitFecharCaixa`, `loadFechamentosHistorico`

## Etapa 9 (última concluída)
**Arquivo criado:** `/assets/js/relatorio-financeiro.js`
**Funções movidas:** `loadRelatorioFinanceiro`, `buscarRelatorioFinanceiro`, `renderBlocoRel`, `renderTabelaChaveValorRel`, `renderTabelaTopProdutosRel`, `renderRelatorioFinanceiro`, `aplicarPeriodoRelatorio`

---

# Estrutura atual do projeto

```
/
├── admin/                         (não confirmado como pasta separada — ver nota na seção Projeto)
├── api/
│   └── config.js                  (serve SUPABASE_URL/SUPABASE_ANON_KEY)
├── assets/
│   ├── css/
│   │   └── painel.css             (Etapa 1)
│   └── js/
│       ├── utils.js               (Etapa 2)
│       ├── auth.js                (Etapa 3)
│       ├── pedidos-utils.js       (Etapa 4)
│       ├── pedidos.js             (Etapa 5)
│       ├── produtos-categorias.js (Etapa 6)
│       ├── clientes-entregadores.js (Etapa 7)
│       ├── financeiro-caixa.js    (Etapa 8)
│       └── relatorio-financeiro.js (Etapa 9)
├── cliente/
│   ├── index.html                 (app do cliente/cardápio, PWA)
│   ├── manifest.json
│   └── sw.js
├── motoboy/
│   └── index.html                 (app do motoboy, PWA)
├── icons/
├── index.html                     (painel admin — script principal + tags <script src> das etapas)
├── manifest.json
└── sw.js
```

**Ordem de carregamento dos scripts no `index.html` (atual, após Etapa 9):**
```html
<script src="/assets/js/utils.js"></script>
<script src="/assets/js/auth.js"></script>
<script src="/assets/js/pedidos-utils.js"></script>
<script src="/assets/js/pedidos.js"></script>
<script src="/assets/js/produtos-categorias.js"></script>
<script src="/assets/js/clientes-entregadores.js"></script>
<script src="/assets/js/financeiro-caixa.js"></script>
<script src="/assets/js/relatorio-financeiro.js"></script>
<script>
  // script principal: boot(), initSupabase(), pedido manual, equipe, marca,
  // variáveis de estado globais, switchView(), status da loja, etc.
</script>
```

---

# Dependências globais importantes

Essas variáveis e funções continuam declaradas no **script principal** do `index.html`, e são usadas pelos arquivos `.js` extraídos (funciona por causa do escopo léxico global compartilhado entre `<script>` clássicos — ver seção de decisões arquiteturais):

**Variáveis de estado (`let`):**
`sb`, `currentUser`, `restauranteInfo`, `restauranteId`, `restauranteSlugAtual`, `produtosCache`, `orders`, `filtroPedidos`, `soundOn`, `audioCtx`, `currentView`, `movimentacoes`, `periodo`, `categoriasCache`, `gruposTamanhoCache`, `produtosAdminCache`, `tipoPrecoAtual`, `camposTamanhoAtivos`, `novosTamanhosState`, `clientesCache`, `entregadoresCache`, `equipeCache`, `convitesCache`, `motoboysAtivosCache`, `horariosSemanaState`, `diaComercialAtualKey`, `resetPedidosInterval`, `horariosLojaAtual`, `statusLojaInterval`, `clienteEncontradoAtual`, `enderecoEncontradoAtual`, `buscaTelefoneTimer`, `caixaAtual`, `deferredInstallPrompt`

**Constantes (`const`):**
`DIAS_SEMANA`, `HORA_RESET_PEDIDOS`, `STATUS_LABEL`, `NEXT_LABEL`, `FLOW`, `STATUS_FINAIS`, `VEICULO_LABEL`, `ROLE_LABEL`

**Funções-chave que permanecem no script principal e são chamadas pelos arquivos extraídos:**
`boot()`, `initSupabase()`, `loadProdutos()` (pedido manual), `showToast()` *(na verdade já em utils.js)*, `inicioDiaComercial()`, `diaComercialData()`, `atualizarSubtituloPedidos()`, `switchView()`, `loadMotoboysAtivos()`

**Funções utilitárias já extraídas e usadas por quase todos os arquivos:** `formatMoeda`, `formatMoedaRel`, `formatData`, `showToast` (todas em `utils.js`, Etapa 2)

---

# Próximas etapas

Candidatas a fragmentação, ainda **não iniciadas**:

1. **`/assets/js/equipe.js`** — mover `loadEquipe`, `renderEquipeTable`, `abrirResetSenhaEquipe`, `redefinirSenhaEquipe`, `toggleAtivoUsuario`, `openMembro`, `closeMembro`, `submitMembro`, `mudarRole`, `removerMembro`, `cancelarConvite`.
2. **`/assets/js/marca.js`** — mover `atualizarLinkCardapioPreview`, `copiarLinkCardapio`, `horariosSemanaPadrao`, `normalizarHorariosSemana`, `renderHorariosGrid`, `toggleDiaAberto`, `atualizarHorarioDia`, `loadMarca`, `submitMarca`, `onLogoMarcaSelecionado` (mantendo `slugify` em `utils.js`, e `uploadImagem` em `produtos-categorias.js`, já movidos).
3. **Pedido manual** — ainda não tem arquivo próprio: `openManualOrder`, `closeManualOrder`, `onFormaPagamentoManualChange`, `onTipoManualChange`, `limparLookupCliente`, `onTelefoneManualInput`, `buscarClientePorTelefone`, `addItemLine`, `submitManualOrder`. Candidato a `/assets/js/pedido-manual.js`.
4. **`app.js` ou "núcleo"** — o que sobrar no script principal depois de tudo isso: `boot()`, `initSupabase()`, `switchView()`, status da loja, drawer mobile, instalação PWA, variáveis de estado globais. Esse núcleo provavelmente deve continuar inline no `index.html` (não tem muito sentido extrair `boot()` pra outro arquivo, já que ele referencia praticamente tudo).

---

# Problemas conhecidos / TODO

- Realtime do motoboy não atualiza instantaneamente (precisa investigar se o app do motoboy tem subscribe de canal Realtime configurado, e revisar o filtro/latência).
- Beep do restaurante (admin) precisa ser revisado (funciona, mas o dono quer reavaliar o som/comportamento).
- Beep do motoboy — avaliar se precisa de som de notificação de novo pedido atribuído.
- Beep pro cliente quando o pedido "sair para entrega" — hoje o cliente só recebe som via canal de tracking em qualquer mudança de status; avaliar se precisa de um som/notificação específica pra esse status.
- PWA white-label por restaurante — hoje o manifest/ícone do app do cliente é único; avaliar se cada restaurante precisa de manifest/ícone próprio pro PWA instalado ter a marca do restaurante.
- Funções administrativas sensíveis (`criar_usuario_equipe`, `remover_usuario_equipe`, `redefinir_senha_usuario`, `remover_restaurante`, `super_admin_*`, `criar_restaurante_com_dono`) estão protegidas por checagem interna de role, mas ainda expostas a `anon` no grant de `EXECUTE` — recomendado revogar `EXECUTE` de `anon` nessas funções (item de higiene, não crítico, pois a checagem interna já bloqueia).
- Bucket de Storage `imagens` permite listagem pública (`LIST`), não só leitura por nome conhecido — baixo risco, mas vale restringir.
- Pasta `admin/` mencionada na estrutura do projeto pelo usuário nunca foi confirmada como existente separadamente do `index.html` da raiz — esclarecer isso no próximo chat se for relevante.

## Correções de segurança já aplicadas nesta conversa (não são mais TODO — só para contexto histórico)
- Policy de auto-inserção em `usuarios` que permitia qualquer usuário autenticado virar `dono` de qualquer restaurante — **removida**.
- RPC `vincular_cliente_por_telefone` permitia sequestro de cadastro de cliente por telefone — **corrigida** (agora só vincula se `auth_user_id` estava vazio, ou se já é o mesmo usuário; bloqueia com erro amigável se pertence a outra pessoa).
- Policy duplicada de INSERT em `pedidos` permitia pedido cross-tenant (cliente de um restaurante inserindo pedido em outro) — **removida** a policy fraca, mantida só a que valida `cliente_id` E `restaurante_id`.
- Total/subtotal/taxa de entrega do pedido eram forjáveis pelo cliente — **corrigido** com 3 triggers (`forcar_taxa_entrega_pedido`, `validar_preco_item_pedido`, `recalcular_totais_pedido`), incluindo tratamento correto de pizza meio a meio (validação por piso de preço mínimo do grupo, não por igualdade exata).
- Tabela `restaurantes` expunha dados de assinatura (`status_assinatura`, `kiwify_subscription_id`, `proximo_vencimento`) publicamente — **corrigido** com a view `restaurantes_publico` (só colunas de vitrine) + remoção da policy pública na tabela original.
- **Bug decorrente da correção acima:** o `cliente/index.html` ainda consultava a tabela `restaurantes` diretamente, causando "Link inválido" nos 3 cardápios públicos — **corrigido**, trocado para `restaurantes_publico`.

---

# Regras obrigatórias para continuar a fragmentação

- Não alterar lógica interna de nenhuma função.
- Não renomear funções.
- Não usar `import`/`export`.
- Não usar `type="module"`.
- Manter todas as funções globais (scripts clássicos).
- Fazer uma etapa por vez — nunca combinar duas fragmentações na mesma resposta.
- Antes de remover qualquer bloco, confirmar que ele existe **exatamente 1 vez** no arquivo de origem.
- Depois de remover, confirmar 0 ocorrências no arquivo de origem e 1 ocorrência no arquivo novo.
- Confirmar via `diff` que a única mudança estrutural no HTML foi a tag `<script src="...">` adicionada.
- Preservar a ordem de carregamento dos scripts (nunca embaralhar).
- Testar e validar cada etapa (o usuário aplica no repositório real e roda o checklist) antes de propor a próxima.
- Sempre entregar ao final de cada etapa: (1) conteúdo completo do arquivo novo, (2) novo `index.html`, (3) lista das funções removidas, (4) confirmação do que **não** foi tocado.

---

# Estado atual do projeto

**Maturidade:** o sistema já tem fluxo completo funcionando em produção-piloto (pelo menos 3 restaurantes de teste: Pizzaria Teste, Donati Cakes, Là Fornatta Pizzeria) — cardápio público, pedido, painel, motoboy, financeiro básico e relatório financeiro. Passou por uma auditoria de segurança RLS completa nesta conversa, com todos os riscos críticos encontrados já corrigidos e validados por teste real no banco (Supabase MCP). A fragmentação do `index.html` está na metade (~44% do arquivo original já modularizado, 9 de aproximadamente 12-13 etapas previstas).

**Próximos objetivos de negócio:** o dono está se preparando para vender e onboardar os primeiros restaurantes reais (fora do ambiente de teste). Antes disso, a prioridade foi eliminar riscos de segurança entre restaurantes (isolamento multi-tenant) — o que já foi feito. A fragmentação do `index.html` é uma iniciativa paralela de manutenibilidade (o arquivo estava ficando grande demais para editar com segurança), não bloqueia a venda, mas reduz risco de erro humano em manutenções futuras.

**Ambiente técnico:** projeto Supabase `vtxugkwazghjgbjxkjal` (região `sa-east-1`, Postgres 17). Deploy via Vercel. Repositório no GitHub (não foi dado acesso direto de escrita ao Claude — todo arquivo é entregue como download pra aplicação manual pelo usuário).

---

# Estrutura do Banco de Dados (visão de alto nível)

## Principais tabelas
- `restaurantes` — dados do restaurante (nome, slug, logo, cor, whatsapp, endereço, instagram, horários, taxa de entrega padrão, dados de assinatura/billing)
- `usuarios` — equipe do restaurante (dono, gerente, atendente, motoboy), ligada a `auth.users` do Supabase
- `motoboys` — extensão de `usuarios` só pra quem é motoboy (veículo, placa, disponibilidade)
- `clientes` — clientes do restaurante, ligados opcionalmente a `auth.users` (sessão anônima)
- `enderecos_cliente` — endereços de entrega do cliente
- `produtos` — itens do cardápio
- `produto_precos` — preço por produto, com ou sem tamanho
- `categorias` — categorias do cardápio
- `grupos_tamanho` / `opcoes_tamanho` — tamanhos e combinação de sabores (ex: pizza meio a meio)
- `pedidos` — o núcleo do sistema (ver seção de relações)
- `itens_pedido` / `itens_pedido_sabores` — itens de cada pedido e seus sabores combinados
- `movimentacoes_financeiras` — entradas (automáticas, de pedido pago) e saídas (despesas manuais)
- `fechamentos_caixa` — abertura/fechamento de caixa por período

## Tabelas auxiliares
- `convites_equipe` — infraestrutura pronta no banco para convite de equipe por e-mail, mas **sem uso real hoje** (0 linhas confirmado, fluxo real de criação de equipe é via RPC direta, não convite)
- `admins_plataforma` — super admins da plataforma (fora do escopo de qualquer restaurante)
- `contadores_diarios` — apoio à numeração sequencial diária de pedidos por restaurante

## Buckets de Storage
- `imagens` (bucket público) — usado tanto para foto de produto quanto para logo do restaurante, com caminho `{restaurante_id}/{pasta}/{arquivo}` (pasta = `produtos` ou `marca`)

---

# Relações importantes do banco

```
restaurantes (1) ────< usuarios (N)
restaurantes (1) ────< motoboys (N, via usuarios.role = 'motoboy')
restaurantes (1) ────< clientes (N)
restaurantes (1) ────< produtos (N)
restaurantes (1) ────< categorias (N)
restaurantes (1) ────< grupos_tamanho (N)
restaurantes (1) ────< pedidos (N)
restaurantes (1) ────< movimentacoes_financeiras (N)
restaurantes (1) ────< fechamentos_caixa (N)
```

```
produtos (N) >──── (1) categorias
produtos (N) >──── (0..1) grupos_tamanho
produtos (1) ────< produto_precos (N)
produto_precos (N) >──── (0..1) opcoes_tamanho
```

```
clientes (1) ────< enderecos_cliente (N)
clientes (1) ────< pedidos (N)
```

```
pedidos (N) >──── (1) restaurantes
pedidos (N) >──── (1) clientes
pedidos (N) >──── (0..1) enderecos_cliente   (só quando tipo = 'entrega')
pedidos (N) >──── (0..1) usuarios            (motoboy_id, só quando tipo = 'entrega')
pedidos (1) ────< itens_pedido (N)
```

```
itens_pedido (N) >──── (1) produtos
itens_pedido (1) ────< itens_pedido_sabores (N)   (só quando o produto combina sabores)
itens_pedido_sabores (N) >──── (1) produtos        (o sabor escolhido)
```

---

# Fluxos operacionais importantes

## Fluxo do cliente
```
Abre link do cardápio (?r=slug)
       ↓
Consulta restaurantes_publico pelo slug
       ↓
Vê cardápio (categorias + produtos + preços)
       ↓
Monta carrinho (produto → tamanho → sabores → quantidade)
       ↓
Inicia checkout
       ↓
Identificação (nome + telefone → sessão anônima Supabase Auth
              → RPC vincular_cliente_por_telefone)
       ↓
Entrega ou retirada (+ endereço, se entrega)
       ↓
Forma de pagamento (+ troco, se dinheiro)
       ↓
Revisão do pedido
       ↓
Confirma pedido → insert em pedidos + itens_pedido (+ itens_pedido_sabores)
       ↓
Acompanha status em tempo real (Realtime, canal por cliente_id)
```

## Fluxo do restaurante (admin)
```
Login (telefone/e-mail + senha)
       ↓
Primeiro acesso? → obrigatório trocar senha provisória antes de continuar
       ↓
Painel de Pedidos (Realtime, canal por restaurante_id)
       ↓
Pedido novo chega → som + toast
       ↓
Avança status (recebido → aceito → em preparo → saiu p/ entrega → entregue)
       ↓ (se retirada, pula "saiu p/ entrega")
Atribui motoboy (se for entrega)
       ↓
Marca como pago (se ainda não foi)
       ↓
Imprime comanda (se precisar)
       ↓
Pedido finalizado → conta pro financeiro/caixa e pros relatórios
```

## Fluxo do motoboy
```
Login (telefone + senha)
       ↓
Bloqueio de acesso ao painel admin (tela "Use o app de entregas")
       ↓
Vê pedidos atribuídos a ele
       ↓
Atualiza status da entrega
       ↓
Pedido marcado como entregue
```

## Fluxo do pedido manual
```
Atendente/dono abre "Lançar Pedido (Manual)" no painel
       ↓
Busca cliente por telefone (debounce automático)
       ↓
Encontrou? → pré-preenche nome e endereço
Não encontrou? → cadastra novo cliente
       ↓
Define tipo (entrega/retirada), itens, forma de pagamento (+ troco)
       ↓
Confirma → mesmo insert em pedidos + itens_pedido do fluxo do cliente
       ↓
Aparece no Painel de Pedidos normalmente (mesmo caminho de todo pedido)
```

---

# Regras de negócio importantes

- **Dia comercial:** o "dia" do sistema não é a meia-noite — vai das 07:00 de um dia até as 06:59 do dia seguinte. Isso afeta a lista de pedidos do painel, a numeração diária de pedidos, e os cálculos de "hoje" no relatório financeiro.
- **Relatórios consideram apenas pedidos com status `entregue` ou `retirado`** — pedido cancelado nunca entra em faturamento, e pedido ainda em andamento também não conta até ser concluído.
- **Primeiro acesso exige troca de senha** — usuário criado pelo dono recebe uma senha provisória e é obrigado a trocá-la antes de usar o painel.
- **Motoboy não acessa o painel admin** — mesmo logando com sucesso, é redirecionado pra uma tela de bloqueio ("Use o app de entregas"); ele só opera pelo app do motoboy.
- **Valores financeiros nunca devem ser confiados no cliente** — total, subtotal, taxa de entrega e preço unitário do item são sempre validados/recalculados no banco (via triggers), nunca aceitos como vieram do frontend. Essa regra já causou um incidente de segurança real nesta conversa (forjamento de total) e está com correção aplicada e testada.

---

# Roadmap do produto

## Curto prazo
- Concluir a fragmentação do `index.html` (equipe, marca, pedido manual)
- Revisar beep/som de notificação (restaurante, motoboy, cliente no "saiu para entrega")
- Investigar e corrigir a latência do Realtime no app do motoboy
- Fechar os itens residuais de segurança de baixa prioridade (revogar `EXECUTE` de `anon` nas funções administrativas, restringir listagem do bucket `imagens`)

## Médio prazo
- PWA white-label por restaurante (manifest/ícone próprio por restaurante instalado)
- Onboarding dos primeiros restaurantes reais (fora do ambiente de teste)
- Melhorias de UX apontadas pelo uso real em horário de pico

## Longo prazo
- Preparar arquitetura para crescer de 3 restaurantes de teste para 20, 100, 300 e 500 restaurantes — reavaliar performance de queries, uso de Realtime em escala, e possível necessidade de índices adicionais conforme o volume de pedidos crescer
- Reavaliar, com dados reais de uso, se algum ponto do sistema precisa de mais estrutura (sem migrar para framework sem necessidade real comprovada)

---

# Situação atual do produto

**Maturidade técnica:** fluxo completo funcionando (cardápio público, pedido, painel, motoboy, financeiro básico, relatório financeiro), auditoria de segurança RLS concluída com todos os riscos críticos corrigidos e validados por teste real no banco, e fragmentação do `index.html` do painel em andamento (~44% concluído).

**Maturidade de negócio:** ambiente de testes com 3 restaurantes fictícios (Pizzaria Teste, Donati Cakes, Là Fornatta Pizzeria). Ainda não há restaurante real/pagante usando o sistema.

**Objetivo atual:** finalizar os últimos ajustes de segurança e manutenibilidade antes de abrir para os primeiros restaurantes reais. A fragmentação do `index.html` não bloqueia a venda — é uma iniciativa paralela de manutenibilidade — mas a segurança multi-tenant (isolamento entre restaurantes) era bloqueante e já foi resolvida.

---

## Checkpoint de Segurança Pós-Fragmentação — Concluído

**Status:** ✅ Concluído
**Data:** 06/07/2026

### Resumo
Foram revisados e corrigidos os principais pontos sensíveis de segurança do EAF Menu após a fragmentação do sistema.

### Itens concluídos
- ✅ Escalonamento de privilégio via tabela `usuarios`
- ✅ Proteção contra sequestro de cliente por telefone
- ✅ Bloqueio de pedido cross-tenant
- ✅ Proteção contra total/subtotal/taxa de entrega forjável
- ✅ Remoção de exposição indevida de dados de assinatura em `restaurantes`
- ✅ Revisão das 10 RPCs sensíveis
- ✅ Revogado `EXECUTE` de `anon` nas 9 RPCs sensíveis
- ✅ Mantida `resolver_email_login` acessível para `anon`, por ser necessária antes do login
- ✅ Bucket `imagens` revisado e mantido como está
- ✅ Removida listagem pública do bucket antigo `produtos-imagens`

### SQL aplicado (resumo)
- `GRANT EXECUTE` explícito para `authenticated` nas 9 RPCs sensíveis
- `REVOKE EXECUTE` de `PUBLIC, anon` nas 9 RPCs sensíveis
- `DROP POLICY` da policy pública de SELECT/listagem do bucket `produtos-imagens`
- Nenhuma alteração aplicada em `resolver_email_login`
- Nenhuma alteração aplicada no bucket `imagens`

### Testes executados e aprovados
1. Login com telefone
2. Login com e-mail
3. Criar membro de equipe
4. Remover membro de equipe
5. Redefinir senha de membro/entregador
6. Relatório financeiro com usuário dono
7. Cliente se identificando por telefone
8. 9 RPCs sensíveis como `anon` puro retornando `42501 permission denied`
9. `resolver_email_login` funcionando como `anon`
10. Bucket `imagens` intacto para upload/exibição
11. Bucket `produtos-imagens` sem listagem pública

### Observações importantes
- `resolver_email_login` deve continuar acessível a `anon`, pois é usada antes da autenticação.
- O bucket `imagens` continua `public=true` de forma intencional, para exibição pública de logo e fotos de produto.
- A remoção da policy em `produtos-imagens` bloqueia listagem pública, mas não necessariamente impede acesso direto a arquivo se alguém já souber a URL e o bucket estiver público.
- Nenhum dado real foi alterado durante os testes funcionais; os testes foram feitos com `ROLLBACK`.

### Conclusão
O sistema está em posição sólida de segurança para entrada dos primeiros restaurantes reais.

---

## Checkpoint Operacional — Horário de Funcionamento

**Status:** ✅ Concluído

### Resumo
Foi ajustado o comportamento visual e operacional relacionado ao horário de funcionamento dos restaurantes.

### Itens concluídos
- ✅ Removido o subtítulo abaixo de "Monitor de Pedidos em Tempo Real" no painel admin
- ✅ Mantida a lógica interna de dia comercial/reset às 7h funcionando por baixo
- ✅ Mantida a exibição de status aberto/fechado no cardápio público
- ✅ Mantido o bloqueio de checkout quando o restaurante está fechado
- ✅ Mantida a dupla validação no cliente:
  - antes de abrir o checkout
  - antes de inserir o pedido em `confirmarPedido()`
- ✅ Ajustada a mensagem para: "Restaurante fechado no momento. Volte no próximo horário de funcionamento."
- ✅ Pedido manual no admin continua permitido fora do horário de funcionamento

### Decisão de produto
O fechamento automático vale para o cardápio público/cliente. O painel admin continua operacional mesmo fora do horário. Pedido manual continua permitido, pois pode representar telefone, balcão, exceção operacional ou pré-venda.

### Arquivos alterados
- `index.html`
- `assets/js/dia-comercial.js`
- `cliente/index.html`

### Não houve alteração em
- SQL
- RLS
- RPCs
- triggers financeiras
- lógica de preço/total
- `horarios_semana`
- pedido manual

---

## Checkpoint UX/Operacional — Pedido Manual estilo PDV

**Status:** ✅ Concluído

### Resumo
A tela de "Lançar pedido manual" foi melhorada para ficar mais parecida com um PDV/caixa, facilitando a operação do atendente.

### Itens concluídos
- ✅ Adicionado campo de pesquisa de produto
- ✅ Produtos/tamanhos agora podem ser filtrados antes de adicionar
- ✅ Itens adicionados aparecem em uma lista clara
- ✅ Adicionado botão para remover item
- ✅ Adicionados controles de quantidade com + e -
- ✅ Produto/tamanho repetido soma quantidade na mesma linha
- ✅ Total visível no modal, atualizado em tempo real
- ✅ Pedido manual continua usando a mesma lógica de criação no banco
- ✅ Pedido manual continua permitido fora do horário de funcionamento

### Arquivos alterados
- `index.html`
- `assets/js/pedido-manual.js`
- `assets/css/painel.css`

### Não houve alteração em
- SQL
- RLS
- RPCs
- triggers financeiras
- lógica de preço/total no banco
- bloqueio de horário no pedido manual

### Decisão de produto
O pedido manual deve funcionar como ferramenta interna de operação. Mesmo com a loja fechada no cardápio público, o atendente pode lançar pedido por telefone, balcão, exceção operacional ou pré-venda.
