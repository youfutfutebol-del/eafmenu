# Modelo Financeiro do EAF Menu

## Status do documento

- F02.01 — Subtotal bruto: aprovado
- F02.02 — Desconto promocional: aprovado
- F02.03 — Desconto de combo: aprovado conceitualmente
- Desconto manual: ainda não definido
- Desconto total: ainda não definido
- Receita líquida: ainda não definida
- Taxa de entrega: regra atual existente, definição formal ainda pendente
- Custo dos produtos: ainda não definido
- Lucro bruto estimado: ainda não definido
- Margem bruta: ainda não definida

---

## 1. Ordem financeira oficial

A ordem financeira atualmente travada é:

preço normal
→ desconto promocional
→ preço de combo
→ desconto manual
→ taxa de entrega
→ total final

As etapas ainda não definidas não devem ser implementadas por suposição.

---

## 2. Subtotal bruto

### Definição

Subtotal bruto é a soma do preço original unitário arredondado de cada item válido multiplicado pela sua quantidade, antes de qualquer desconto e antes da taxa de entrega.

### Fórmula

subtotal_bruto = Σ (preco_original_unitario × quantidade)

### Regras

- O preço original representa o valor vigente no momento da confirmação do pedido.
- Alterações futuras no cadastro não modificam pedidos antigos.
- Produto com tamanho usa o preço normal da opção escolhida.
- Produtos com múltiplos sabores seguem, atualmente, a média dos preços dos sabores escolhidos.
- A política de média poderá ser revista por decisão futura de produto.
- Quantidade válida é número inteiro maior ou igual a 1.
- Preço original válido deve ser maior que zero.
- Preço zero somente poderá existir com uma futura regra explícita de brinde.
- Item inválido não pode ser descartado silenciosamente.
- Qualquer item inválido torna o pedido inteiro inválido para confirmação.
- Carrinho vazio possui subtotal de R$ 0,00, mas não constitui pedido válido.

### Arredondamento

1. Determinar o preço original unitário.
2. Arredondar o preço unitário para duas casas.
3. Multiplicar pela quantidade.
4. Arredondar o total da linha.
5. Somar as linhas.
6. Arredondar o subtotal bruto final.

Nunca utilizar truncamento.

---

## 3. Desconto promocional

### Definição

Desconto promocional é a redução automática aplicada ao preço original de unidades elegíveis por uma promoção ativa e válida no momento da confirmação do pedido.

### Posição

É aplicado depois do preço original e antes do combo, desconto manual e taxa de entrega.

### Modalidades conceituais

- percentual por unidade elegível;
- valor fixo por unidade elegível.

Uma promoção não deve misturar percentual e valor fixo simultaneamente.

### Unidades elegíveis

quantidade_nao_elegivel =
quantidade_total - quantidade_elegivel

desconto_promocional_total_linha =
desconto_promocional_unitario × quantidade_elegivel

total_apos_promocao_linha =
(preco_apos_promocao_unitario × quantidade_elegivel)
+
(preco_original_unitario × quantidade_nao_elegivel)

Unidades não elegíveis permanecem no preço original.

### Promoção inválida

Uma promoção inválida:

- não é aplicada;
- gera desconto promocional de R$ 0,00;
- mantém o item no preço original;
- não invalida um item financeiramente válido;
- deve gerar registro ou alerta futuro para o restaurante.

### Múltiplas promoções

Não acumular promoções automáticas sobre a mesma unidade.

Ordem de seleção:

1. menor preço efetivamente cobrado;
2. prioridade configurada pelo restaurante;
3. início de vigência mais antigo.

### Múltiplos sabores

A promoção só é aplicada quando todos os sabores escolhidos forem elegíveis para a mesma promoção e para a mesma opção de tamanho.

### Vigência

A promoção deve estar ativa e válida no momento da confirmação do pedido.

Timezone oficial:

America/Sao_Paulo

### Taxa de entrega

O desconto promocional não reduz a taxa de entrega.

### Preservação histórica

O pedido deve preservar:

- preço original;
- promoção aplicada;
- desconto promocional;
- preço após promoção.

Mudanças futuras na promoção não recalculam pedidos antigos.

---

## 4. Desconto de combo

### Definição

Desconto de combo é a redução aplicada sobre o valor pós-promoção de um conjunto de produtos que atende integralmente às condições de um combo válido.

### Posição

O combo é avaliado depois do desconto promocional e antes do desconto manual e da taxa de entrega.

### Base de cálculo

base_combo =
soma dos valores pós-promoção das unidades participantes

desconto_combo =
base_combo - preco_combo

valor_apos_combo =
base_combo - desconto_combo

O desconto promocional permanece registrado separadamente.

### Elegibilidade

O combo deve declarar:

- produtos participantes;
- quantidades obrigatórias;
- tamanhos permitidos;
- regras para sabores;
- vigência;
- status ativo;
- limite de aplicações;
- modalidade financeira.

Todas as condições devem ser atendidas.

### Modalidades conceituais

- preço fechado do conjunto;
- desconto fixo sobre o conjunto;
- desconto percentual sobre o conjunto.

As modalidades disponíveis na implementação ainda precisam de decisão de produto.

Uma mesma regra não deve misturar modalidades.

### Número de aplicações

O número de aplicações corresponde ao maior número inteiro de conjuntos completos que pode ser formado.

Unidades excedentes permanecem pelo valor pós-promoção.

### Consumo exclusivo

Uma mesma unidade não pode participar de dois combos simultaneamente.

### Múltiplos combos elegíveis

Ordem de seleção:

1. prioridade configurada pelo restaurante;
2. maior desconto total;
3. início de vigência mais antigo.

Não acumular combos sobre a mesma unidade.

### Combo sem vantagem

Se o preço do combo for igual ou superior à base do conjunto:

- o combo não é aplicado;
- o desconto de combo é R$ 0,00;
- os itens permanecem pelos valores pós-promoção.

O combo nunca aumenta o preço.

### Múltiplos sabores

Um item de múltiplos sabores só participa do combo quando todos os sabores e o tamanho forem elegíveis para a mesma regra.

O item não pode ser parcialmente dividido entre combo e preço normal.

### Combo inválido

Um combo inválido:

- não é aplicado;
- gera desconto de combo de R$ 0,00;
- não invalida itens financeiramente válidos;
- deve gerar registro ou alerta futuro para o restaurante.

### Vigência

O combo deve estar ativo e válido no momento da confirmação do pedido.

Timezone oficial:

America/Sao_Paulo

### Preservação histórica

O pedido deve preservar separadamente:

- preço original;
- desconto promocional;
- valor após promoção;
- combo aplicado;
- desconto de combo;
- valor após combo.

Mudanças futuras no combo não recalculam pedidos antigos.

---

## 5. Decisões ainda pendentes

Ainda não estão definidas:

- modalidades de promoção que serão disponibilizadas na interface;
- modalidades de combo que serão disponibilizadas;
- estrutura técnica das promoções e combos;
- desconto manual;
- desconto total;
- receita líquida;
- taxa de entrega dentro do novo modelo;
- custo dos produtos;
- lucro bruto estimado;
- margem bruta;
- preço original versus preço efetivamente cobrado no schema;
- implementação técnica da ordem de cálculo;
- políticas de brinde ou gratuidade;
- alterações necessárias no banco e frontend.

Nenhum desses pontos deve ser implementado por suposição.
