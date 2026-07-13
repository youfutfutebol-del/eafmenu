# Modelo Financeiro do EAF Menu

## Status do documento

- F02.01 — Subtotal bruto: aprovado
- F02.02 — Desconto promocional: aprovado
- F02.03 — Desconto de combo: aprovado conceitualmente
- F02.04 — Desconto manual: aprovado
- F02.05 — Desconto total: aprovado
- F02.06 — Receita líquida: aprovada
- F02.07 — Taxa de entrega: aprovada
- F02.08 — Custo dos produtos: aprovado
- F02.09 — Lucro bruto estimado: aprovado
- F02.10 — Margem bruta estimada: aprovada

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

## 5. Desconto manual

### Definição

Desconto manual é a redução deliberada aplicada por um usuário autorizado do restaurante sobre o valor dos produtos do pedido depois dos descontos promocionais e de combo e antes da taxa de entrega.

Diferentemente dos descontos automáticos, depende de ação humana consciente, motivo obrigatório e identificação de quem aplicou e, quando necessário, de quem autorizou.

### Posição na ordem financeira

O desconto manual é aplicado:

- depois do desconto promocional;
- depois do desconto de combo;
- antes da taxa de entrega;
- antes do total final.

### Base de cálculo

base_desconto_manual =
subtotal_bruto
- desconto_promocional_total
- desconto_combo_total

O desconto manual não incide sobre:

- taxa de entrega;
- troco;
- custo dos produtos;
- valores de caixa;
- movimentações financeiras.

### Modalidades conceituais

O desconto manual pode ser:

- valor fixo em reais;
- percentual sobre a base do desconto manual.

Uma mesma aplicação utiliza apenas uma modalidade.

A interface futura decidirá se ambas serão oferecidas.

### Escopo

O desconto manual é aplicado sobre o pedido como um todo, considerando somente o valor dos produtos depois de promoção e combo.

O rateio entre os itens será definido posteriormente.

Existe no máximo um desconto manual consolidado por pedido.

Antes da confirmação, a edição substitui a configuração anterior; descontos manuais independentes não são acumulados.

### Fórmulas

Para percentual:

desconto_manual =
arredondar(base_desconto_manual × percentual_manual, 2)

Para valor fixo:

desconto_manual =
valor informado, validado e arredondado para duas casas

Valor dos produtos depois do desconto manual:

valor_produtos_apos_manual =
base_desconto_manual - desconto_manual

Total final:

total_final =
valor_produtos_apos_manual + taxa_entrega

Fórmula de conferência:

desconto_manual =
base_desconto_manual - valor_produtos_apos_manual

### Limites

O desconto manual:

- não pode ser negativo;
- não pode ser nulo quando declarado como aplicado;
- não pode ser maior que a base disponível;
- não pode gerar valor dos produtos negativo;
- não pode alterar o preço original;
- não pode apagar descontos anteriores;
- não pode alterar o custo dos produtos;
- não pode reduzir a taxa de entrega;
- deve possuir no máximo duas casas decimais.

### Desconto de até 100%

O restaurante pode aplicar desconto manual de até 100% sobre o valor dos produtos, desde que a operação esteja autorizada.

Isso pode resultar em:

valor_produtos_apos_manual = R$ 0,00

A taxa de entrega continua sendo cobrada normalmente quando existir.

Preço original zero continua sendo inválido. O que pode chegar a zero é o valor efetivamente cobrado pelos produtos depois do desconto.

### Tentativa inválida

Uma tentativa de desconto manual inválida não deve ser ignorada silenciosamente.

Enquanto a tentativa permanecer ativa:

- o desconto não é aplicado;
- os produtos permanecem no valor depois de promoção e combo;
- a confirmação do pedido fica bloqueada.

O operador deve:

- corrigir o desconto;
- remover a tentativa;
- ou obter a autorização necessária.

São exemplos de tentativa inválida:

- valor negativo;
- percentual negativo;
- percentual superior a 100%;
- valor superior à base;
- valor fixo e percentual simultâneos;
- modalidade não identificada;
- valor não numérico;
- motivo ausente;
- autorização obrigatória ausente.

### Motivo obrigatório

Todo desconto manual confirmado deve possuir motivo:

- não vazio;
- não formado somente por espaços;
- suficiente para auditoria;
- preservado historicamente.

O formato do campo será definido posteriormente.

### Autoria e autorização

O modelo distingue:

aplicado_por =
usuário que inseriu o desconto

autorizado_por =
usuário que aprovou o desconto quando houver autorização adicional

Os dois podem ser a mesma pessoa quando o perfil possuir autorização direta.

As permissões e o PIN serão definidos na Fase 08.

### Preservação histórica

Depois da confirmação, devem permanecer preservados:

- modalidade utilizada;
- valor ou percentual informado;
- valor final do desconto;
- motivo;
- usuário que aplicou;
- usuário que autorizou;
- valor dos produtos antes do desconto;
- valor dos produtos depois do desconto.

Mudanças futuras de usuário, perfil, PIN ou permissões não alteram pedidos antigos.

### Taxa de entrega

O desconto manual não reduz a taxa de entrega.

Uma futura cortesia ou isenção de frete deverá ser tratada como regra separada.

### Margem e prejuízo

A decisão financeira pertence ao restaurante.

O sistema poderá alertar sobre margem baixa ou prejuízo, mas não deve impedir um desconto manual matematicamente válido e devidamente autorizado somente por causa do resultado financeiro.

Nunca utilizar a expressão “lucro líquido” para receita menos custo dos produtos.

### Arredondamento

1. Utilizar a base após promoção e combo já arredondada.
2. Calcular o desconto manual.
3. Arredondar o desconto para duas casas.
4. Subtrair o desconto da base.
5. Arredondar o valor dos produtos após o desconto.
6. Adicionar posteriormente a taxa de entrega.
7. Arredondar o total final para duas casas.

Nunca utilizar truncamento.

---

## 6. Desconto total

### Definição

Desconto total é o valor agregado e auditável de todas as reduções comerciais efetivamente aplicadas aos produtos do pedido.

É um valor derivado da soma de:

- desconto promocional total;
- desconto de combo total;
- desconto manual.

Não é uma nova modalidade de desconto e não pode ser digitado ou editado diretamente.

### Fórmula oficial

desconto_total =
desconto_promocional_total
+ desconto_combo_total
+ desconto_manual

Com arredondamento:

desconto_total =
arredondar(
  desconto_promocional_total
  + desconto_combo_total
  + desconto_manual,
  2
)

Cada componente já deve chegar válido e arredondado conforme sua própria etapa.

### Valor dos produtos após descontos

valor_produtos_apos_descontos =
arredondar(subtotal_bruto - desconto_total, 2)

Esse valor é equivalente ao valor dos produtos após desconto manual definido na F02.04.

Fórmula de conferência:

desconto_total =
subtotal_bruto - valor_produtos_apos_descontos

### Componentes separados

O pedido deve preservar separadamente:

- subtotal bruto;
- desconto promocional total;
- desconto de combo total;
- desconto manual;
- desconto total;
- valor dos produtos após todos os descontos.

O desconto total não substitui, apaga ou oculta seus componentes.

### Ausência de descontos

Quando nenhum desconto for aplicado:

desconto_promocional_total = R$ 0,00
desconto_combo_total = R$ 0,00
desconto_manual = R$ 0,00

Resultado:

desconto_total = R$ 0,00
valor_produtos_apos_descontos = subtotal_bruto

A ausência de desconto deve ser representada por zero explícito, nunca por valor nulo ou indefinido no cálculo consolidado.

### Limites obrigatórios

O desconto total:

- não pode ser negativo;
- não pode ser maior que o subtotal bruto;
- não pode produzir valor dos produtos negativo;
- não inclui taxa de entrega;
- não pode ser informado diretamente pelo usuário;
- deve corresponder exatamente à soma dos componentes válidos;
- deve possuir duas casas decimais;
- não pode esconder divergências financeiras.

Regras:

0 ≤ desconto_total ≤ subtotal_bruto

valor_produtos_apos_descontos ≥ R$ 0,00

### Desconto total de até 100%

O desconto total pode atingir 100% do subtotal bruto quando a combinação válida dos descontos resultar em gratuidade integral dos produtos.

Isso pode resultar em:

valor_produtos_apos_descontos = R$ 0,00

A taxa de entrega continua fora do desconto total e pode ser adicionada posteriormente.

O desconto total nunca pode superar o subtotal bruto.

### Componentes inválidos

Promoção inválida:

desconto_promocional_total = R$ 0,00

Não bloqueia o pedido, desde que os itens sejam financeiramente válidos.

Combo inválido:

desconto_combo_total = R$ 0,00

Não bloqueia o pedido, desde que os itens sejam financeiramente válidos.

Desconto manual inválido:

- não entra no desconto total definitivo;
- bloqueia a confirmação enquanto a tentativa inválida permanecer ativa;
- deve ser corrigido, removido ou autorizado.

O sistema não deve aceitar um desconto total definitivo ignorando silenciosamente uma tentativa manual inválida.

### Inconsistências financeiras

Existe inconsistência quando:

desconto_total
≠
desconto_promocional_total
+ desconto_combo_total
+ desconto_manual

ou quando:

valor_produtos_apos_descontos
≠
subtotal_bruto - desconto_total

Uma inconsistência deve bloquear a confirmação do pedido até que o cálculo seja corrigido.

O sistema não deve escolher silenciosamente um dos valores divergentes.

### Relação com taxa de entrega

O desconto total não inclui e não reduz a taxa de entrega.

A fórmula futura do total final será:

total_final =
valor_produtos_apos_descontos + taxa_entrega

Uma eventual gratuidade de frete será uma regra separada.

### Preservação histórica

Depois da confirmação, devem permanecer preservados:

- subtotal bruto;
- desconto promocional total;
- desconto de combo total;
- desconto manual;
- desconto total;
- valor dos produtos após descontos;
- promoções e combos aplicados;
- motivo e autoria do desconto manual;
- valores utilizados no momento da confirmação.

Mudanças futuras de preços, promoções, combos, usuários ou permissões não recalculam pedidos antigos.

### Arredondamento

1. Receber o desconto promocional total já arredondado.
2. Receber o desconto de combo total já arredondado.
3. Receber o desconto manual já arredondado.
4. Somar os três componentes.
5. Arredondar o desconto total para duas casas.
6. Subtrair o desconto total do subtotal bruto.
7. Arredondar o valor dos produtos após descontos.
8. Validar as fórmulas de conferência.

Nunca utilizar truncamento.

---

## 7. Receita líquida

### Definição

Receita líquida é o valor dos produtos efetivamente cobrado do cliente depois de todos os descontos comerciais válidos e antes da taxa de entrega.

Ela representa a receita de venda dos produtos depois de:

- desconto promocional;
- desconto de combo;
- desconto manual.

Ela não representa:

- total final do pedido;
- valor recebido em caixa;
- lucro;
- custo;
- margem;
- taxa de entrega;
- troco;
- movimentação financeira.

### Natureza derivada

Receita líquida é um valor derivado.

Não pode ser digitada ou editada diretamente.

Fórmulas oficiais:

receita_liquida =
subtotal_bruto - desconto_total

receita_liquida =
arredondar(subtotal_bruto - desconto_total, 2)

Equivalência obrigatória:

receita_liquida =
valor_produtos_apos_descontos

`receita_liquida` e `valor_produtos_apos_descontos` são a mesma grandeza e não podem apresentar valores diferentes.

### Posição na ordem financeira

A receita líquida é determinada:

- depois do desconto promocional;
- depois do desconto de combo;
- depois do desconto manual;
- antes da taxa de entrega;
- antes do total final.

Ordem consolidada:

subtotal bruto
→ descontos
→ receita líquida
→ taxa de entrega
→ total final

### Relação com taxa de entrega

A receita líquida não inclui taxa de entrega.

A taxa de entrega será adicionada posteriormente:

total_final =
receita_liquida + taxa_entrega

Uma eventual gratuidade ou redução de frete deverá ser tratada como regra separada.

### Relação com o total final

Receita líquida e total final são grandezas diferentes.

Exemplo:

Subtotal bruto: R$ 100,00
Desconto total: R$ 20,00
Receita líquida: R$ 80,00
Taxa de entrega: R$ 8,00
Total final: R$ 88,00

Nesse exemplo, a receita líquida permanece R$ 80,00.

### Relação com pagamento

A receita líquida é calculada independentemente do estado de pagamento do pedido.

Portanto:

- pedido não pago pode possuir receita líquida calculada;
- marcar o pedido como pago não altera a receita líquida;
- desmarcar o pedido como pago não recalcula a receita líquida;
- forma de pagamento não altera a receita líquida;
- troco não altera a receita líquida.

Receita líquida calculada e entrada de caixa recebida são conceitos distintos.

### Relação com cancelamento

O pedido confirmado conserva sua receita líquida histórica mesmo após cancelamento.

Porém, um pedido cancelado não deve ser incluído nos consolidados de receitas válidas.

O cancelamento:

- não apaga a receita líquida registrada;
- não recalcula os valores históricos;
- deve ser considerado nos relatórios por meio do status do pedido.

A relação entre cancelamento, pagamento, estorno e movimentações financeiras será definida posteriormente.

### Limites obrigatórios

A receita líquida:

- não pode ser negativa;
- não pode ser maior que o subtotal bruto;
- deve corresponder ao subtotal bruto menos o desconto total;
- deve possuir duas casas decimais;
- pode ser igual a zero;
- não inclui taxa de entrega;
- não pode ser editada diretamente;
- deve ser derivada de valores financeiros válidos.

Regra:

0 ≤ receita_liquida ≤ subtotal_bruto

### Receita líquida igual a zero

A receita líquida pode ser igual a zero quando os descontos válidos atingirem 100% do subtotal bruto.

Exemplo:

Subtotal bruto: R$ 80,00
Desconto total: R$ 80,00
Receita líquida: R$ 0,00
Taxa de entrega: R$ 8,00
Total final: R$ 8,00

Isso não significa:

- preço original zero;
- pedido sem itens;
- custo zero;
- ausência de venda;
- taxa de entrega gratuita.

### Ausência de descontos

Quando:

desconto_total = R$ 0,00

então:

receita_liquida = subtotal_bruto

### Inconsistências financeiras

Existe inconsistência quando:

receita_liquida
≠
subtotal_bruto - desconto_total

ou quando:

receita_liquida
≠
valor_produtos_apos_descontos

Uma divergência deve bloquear a confirmação do pedido até a correção do cálculo.

O sistema não deve escolher silenciosamente um dos valores divergentes.

### Preservação histórica

Depois da confirmação do pedido, devem permanecer preservados:

- subtotal bruto;
- desconto total;
- componentes do desconto;
- receita líquida;
- valores utilizados no momento da confirmação.

Mudanças futuras em preços, promoções, combos, desconto manual, permissões ou taxa de entrega não recalculam a receita líquida de pedidos antigos.

### Relação com custo e lucro bruto estimado

A receita líquida será usada posteriormente na fórmula:

lucro_bruto_estimado =
receita_liquida - custo_dos_produtos

Receita líquida não é lucro.

Esta seção não define custo dos produtos, lucro bruto estimado ou margem bruta.

Nunca utilizar a expressão “lucro líquido” para esse cálculo.

### Arredondamento

1. Receber o subtotal bruto já arredondado.
2. Receber o desconto total já arredondado.
3. Subtrair o desconto total do subtotal bruto.
4. Arredondar a receita líquida para duas casas.
5. Conferir a equivalência com `valor_produtos_apos_descontos`.
6. Validar os limites financeiros.

Nunca utilizar truncamento.

---

## 8. Taxa de entrega

### Definição

Taxa de entrega é o valor cobrado pelo serviço de levar o pedido ao endereço do cliente.

É uma grandeza separada do valor dos produtos e é adicionada somente depois que a receita líquida foi determinada.

Ela não representa:

- preço de produto;
- desconto;
- custo dos produtos;
- troco;
- pagamento recebido;
- lucro;
- movimentação financeira;
- valor de retirada.

### Posição na ordem financeira

A ordem financeira é:

subtotal bruto
→ desconto promocional
→ desconto de combo
→ desconto manual
→ receita líquida
→ taxa de entrega
→ total final

A taxa de entrega não participa do subtotal bruto, do desconto total ou da receita líquida.

### Fórmulas oficiais

total_final =
receita_liquida + taxa_entrega

Com arredondamento:

total_final =
arredondar(receita_liquida + taxa_entrega, 2)

Fórmula de conferência:

taxa_entrega =
total_final - receita_liquida

### Pedido para entrega

Em pedido para entrega:

- a taxa deve ser obtida da regra válida do restaurante;
- deve ser determinada no momento da confirmação;
- deve possuir valor financeiro válido;
- deve permanecer registrada historicamente;
- mudanças futuras na configuração não devem alterar pedidos antigos.

O modelo atual utiliza a taxa padrão configurada pelo restaurante.

Não existe atualmente cálculo por distância, CEP, bairro ou zona.

### Pedido para retirada

Em pedido para retirada:

taxa_entrega = R$ 0,00

A taxa zero é uma regra válida e obrigatória para retirada.

O total final será:

total_final = receita_liquida

### Entrega gratuita

Uma entrega pode possuir taxa igual a zero somente quando existir regra explícita de gratuidade ou frete grátis.

Devem ser diferenciadas:

- taxa zero explicitamente válida;
- taxa ausente;
- taxa inválida.

Taxa zero válida não deve ser tratada como erro.

A gratuidade de frete é separada dos descontos aplicados aos produtos.

### Taxa ausente ou inválida

São exemplos de taxa inválida:

- valor negativo;
- valor não numérico;
- valor nulo ou ausente em uma entrega sem gratuidade explícita;
- configuração incompatível com o restaurante;
- taxa não determinável no momento da confirmação.

Para pedido de entrega, taxa ausente ou inválida bloqueia a confirmação até que exista uma taxa válida ou uma gratuidade explicitamente definida.

O sistema não deve:

- converter silenciosamente taxa ausente em zero;
- concluir o pedido com valor indefinido;
- confiar no valor enviado pelo navegador sem validação;
- escolher uma taxa arbitrária.

Para retirada, taxa zero é válida e obrigatória.

### Relação com descontos

- desconto promocional não reduz a taxa de entrega;
- desconto de combo não reduz a taxa de entrega;
- desconto manual não reduz a taxa de entrega;
- desconto total não inclui a taxa de entrega.

Mesmo quando:

receita_liquida = R$ 0,00

a taxa continua sendo cobrada, salvo gratuidade explícita.

### Desconto de 100% nos produtos

Exemplo:

Subtotal bruto: R$ 80,00
Desconto total: R$ 80,00
Receita líquida: R$ 0,00
Taxa de entrega: R$ 8,00
Total final: R$ 8,00

Desconto integral nos produtos não transforma automaticamente a entrega em gratuita.

### Relação com pagamento

A taxa e o total final são calculados independentemente do pagamento.

Portanto:

- pedido não pago já possui taxa calculada;
- marcar como pago não altera a taxa;
- desmarcar como pago não recalcula a taxa;
- forma de pagamento não altera a taxa;
- troco não altera a taxa.

Taxa calculada e entrada financeira recebida são conceitos distintos.

### Relação com cancelamento

Depois da confirmação:

- a taxa histórica permanece registrada;
- o cancelamento não apaga nem recalcula a taxa;
- pedidos cancelados não entram nos consolidados de vendas válidas;
- estorno ou devolução da taxa serão tratados posteriormente.

### Momento de fixação

A taxa deve ser fixada no momento da confirmação do pedido.

Depois disso:

- mudanças na taxa do restaurante não alteram pedidos antigos;
- mudanças na modalidade de entrega não recalculam pedidos antigos;
- o valor deve permanecer auditável.

### Limites obrigatórios

A taxa de entrega:

- não pode ser negativa;
- pode ser zero quando explicitamente válida;
- deve possuir duas casas decimais;
- não pode ser editada diretamente pelo cliente;
- deve ser validada pela regra do restaurante;
- não pode ser reduzida por descontos dos produtos;
- deve ser determinada antes da confirmação;
- deve permanecer preservada historicamente.

Regra:

taxa_entrega ≥ R$ 0,00

### Inconsistências financeiras

Existe inconsistência quando:

total_final
≠
receita_liquida + taxa_entrega

Também existe inconsistência quando um pedido de retirada possui taxa de entrega diferente de zero.

Uma divergência deve bloquear a confirmação até a correção.

O sistema não deve corrigir silenciosamente um total divergente.

### Preservação histórica

Depois da confirmação, devem permanecer preservados:

- tipo do pedido;
- receita líquida;
- taxa de entrega;
- total final;
- regra usada para determinar a taxa;
- valores utilizados no momento da confirmação.

Mudanças futuras na configuração do restaurante não recalculam pedidos antigos.

### Arredondamento

1. Receber a receita líquida já arredondada.
2. Determinar uma taxa de entrega válida.
3. Arredondar a taxa para duas casas.
4. Somar receita líquida e taxa.
5. Arredondar o total final para duas casas.
6. Validar a fórmula de conferência.

Nunca utilizar truncamento.

### Divergência com o comportamento atual

A auditoria da Fase 01 identificou que o banco atual utiliza comportamento equivalente a:

coalesce(taxa_entrega_padrao, 0)

Isso significa que, atualmente, uma taxa ausente pode ser transformada silenciosamente em zero.

Esse comportamento diverge da regra aprovada nesta F02.07, segundo a qual uma entrega sem taxa válida ou gratuidade explícita deve ser bloqueada.

Esta divergência deve permanecer registrada como pendência de implementação.

Não alterar o banco nesta missão.

---

## 9. Custo dos produtos

### Definição

Custo dos produtos é a soma dos custos unitários internos dos itens utilizados em um pedido, multiplicados pelas respectivas quantidades.

Representa uma estimativa interna do restaurante e será usado futuramente no cálculo de lucro bruto estimado.

Não representa:

- preço original de venda;
- preço efetivamente cobrado;
- desconto;
- taxa de entrega;
- total final;
- valor recebido;
- movimentação de caixa;
- despesas gerais;
- impostos;
- salários;
- aluguel;
- comissão de plataforma;
- lucro.

### Natureza interna

O custo dos produtos:

- é informação interna do restaurante;
- não deve ser exibido ao cliente;
- não altera o valor cobrado;
- não interfere na confirmação do pedido;
- não limita promoções, combos ou descontos;
- será utilizado em relatórios, simuladores e alertas financeiros.

Mesmo quando uma venda resultar em margem baixa ou prejuízo estimado, o sistema pode alertar, mas não deve bloquear a venda.

### Fórmulas oficiais

Para uma linha com custo conhecido:

custo_total_linha =
custo_unitario_historico × quantidade

Com arredondamento:

custo_total_linha =
arredondar(custo_unitario_historico × quantidade, 2)

Quando todos os custos forem conhecidos:

custo_dos_produtos =
arredondar(Σ custo_total_linha, 2)

### Custo unitário

Custo unitário é o valor interno estimado para produzir ou adquirir uma unidade do item.

Deve ser:

- numérico;
- maior ou igual a zero;
- armazenado com duas casas decimais;
- definido pelo restaurante;
- separado do preço de venda.

Custo zero explicitamente cadastrado é válido.

Custo ausente ou inválido não deve ser convertido em zero.

### Estados oficiais do custo

A representação oficial é:

estado_custo =
conhecido | parcial | desconhecido

#### Conhecido

Todos os itens e composições possuem custos válidos e determináveis.

estado_custo = conhecido

custo_dos_produtos =
soma completa dos custos totais das linhas

Somente neste estado `custo_dos_produtos` representa um total completo e confiável.

#### Parcial

Algumas linhas possuem custo conhecido e outras possuem custo ausente ou inválido.

estado_custo = parcial

custo_conhecido_parcial =
soma somente das linhas com custo conhecido

Nesse estado:

- `custo_conhecido_parcial` pode ser exibido como informação auxiliar;
- nunca deve ser apresentado como `custo_dos_produtos`;
- deve ser indicada a quantidade de itens ou unidades sem custo;
- lucro bruto estimado e margem bruta não podem ser apresentados como completos e confiáveis.

#### Desconhecido

Nenhuma linha possui custo válido e determinável.

estado_custo = desconhecido

Nesse estado:

- o custo total não pode ser calculado;
- não deve ser apresentado R$ 0,00 como custo dos produtos;
- lucro bruto estimado e margem bruta não podem ser apresentados como valores confiáveis.

Não existe um quarto estado.

### Custo ausente ou inválido

Quando o custo não estiver cadastrado:

- deve ser tratado como desconhecido;
- não bloqueia a venda;
- não invalida o pedido;
- não altera o valor cobrado;
- torna incompleto o cálculo de custo e rentabilidade;
- deve gerar indicação de informação incompleta ao restaurante.

São exemplos de custo inválido:

- valor negativo;
- valor não numérico;
- valor infinito;
- configuração incompatível com o produto ou variação;
- custo não determinável.

Custo inválido também deve ser tratado como desconhecido, nunca como zero.

### Produto sem variação

Para produto sem tamanho ou variação:

custo_unitario_historico =
custo cadastrado para o produto

O custo é multiplicado pela quantidade do item.

### Produto com tamanho ou variação

Para produto com tamanho ou variação:

custo_unitario_historico =
custo específico da opção selecionada

Não utilizar automaticamente o custo de outro tamanho.

Se não existir custo específico para a opção selecionada, o custo deve ser tratado como desconhecido.

Uma futura regra de custo compartilhado entre variações dependerá de decisão explícita.

### Produtos com múltiplos sabores

O custo de um item com múltiplos sabores não utiliza a média dos preços de venda.

Preço de venda e custo são grandezas diferentes.

Regra conceitual:

custo_da_composicao =
soma dos custos proporcionais às partes efetivamente utilizadas

Divisões como 50% para cada sabor ou 1/3 para cada sabor somente são válidas quando representam a composição real do item.

Não presumir divisão igual quando:

- as porções forem diferentes;
- existir sabor predominante;
- o restaurante configurar outra proporção;
- ingredientes compartilhados possuírem regra própria.

Enquanto as proporções reais e todos os custos necessários não forem determináveis:

custo_da_composicao = desconhecido

### Produtos participantes de combo

O preço ou desconto do combo não altera o custo dos produtos participantes.

custo_combo =
soma dos custos históricos dos itens utilizados na aplicação

Unidades excedentes fora do combo mantêm seus próprios custos históricos.

Quando algum item necessário ao combo possuir custo desconhecido:

- o custo consolidado do combo fica parcial ou desconhecido;
- o combo continua podendo ser vendido;
- nenhum custo deve ser inventado ou convertido em zero.

### Adicionais futuros

Quando adicionais forem implementados:

- cada adicional poderá possuir custo próprio;
- esse custo deverá entrar no custo do item;
- o custo histórico deverá ser preservado.

O sistema atual não possui essa estrutura formalmente implementada.

### Embalagens e outros custos diretos

Devem ser diferenciados:

- custo dos produtos;
- outros custos diretos do pedido.

Outros custos diretos podem incluir embalagem, recipiente, talher, molho, insumo adicional ou material descartável.

Esses custos não devem ser misturados automaticamente ao custo dos produtos sem regra específica.

### Momento de fixação

O custo deve ser fixado como snapshot no momento da confirmação do pedido.

Depois da confirmação:

- alterações futuras no cadastro de custo não modificam pedidos antigos;
- o pedido preserva o custo utilizado no momento da venda;
- relatórios históricos utilizam o valor preservado;
- o cadastro atual não deve recalcular pedidos antigos.

Se o custo estiver ausente ou inválido na confirmação, o estado parcial ou desconhecido também deve ser preservado historicamente.

Cadastrar o custo posteriormente não deve completar ou recalcular automaticamente pedidos antigos.

### Relação com descontos

Promoções, combos e descontos manuais:

- reduzem a receita líquida;
- não reduzem o custo dos produtos;
- não alteram o custo unitário histórico;
- não recalculam o custo do item.

### Relação com quantidade

Quantidade válida continua sendo número inteiro maior ou igual a 1.

custo_total_linha =
custo_unitario_historico × quantidade

Quantidade inválida continua sendo tratada conforme as regras da F02.01.

### Relação com pagamento e cancelamento

O custo é independente do pagamento.

Marcar ou desmarcar um pedido como pago não altera ou recalcula o custo.

Depois da confirmação, mesmo que o pedido seja cancelado:

- o custo histórico permanece registrado;
- o cancelamento não apaga ou recalcula o custo;
- pedidos cancelados não entram nos consolidados de vendas válidas;
- o custo preservado continua disponível para auditoria.

Baixa de estoque, desperdício e estorno de custo não são definidos nesta etapa.

### Relação futura com lucro bruto estimado e margem

Lucro bruto estimado e margem bruta somente podem ser apresentados como valores completos quando:

estado_custo = conhecido

Quando o estado for parcial ou desconhecido:

- o pedido continua válido;
- a venda não é bloqueada;
- a receita líquida continua válida;
- o sistema deve indicar que a informação de custo e rentabilidade está incompleta;
- não deve apresentar lucro parcial como se fosse lucro bruto estimado total.

Não utilizar a expressão “lucro líquido” para receita menos custo dos produtos.

### Inconsistências

Quando `estado_custo = conhecido`:

custo_dos_produtos =
soma completa dos custos totais das linhas

Quando `estado_custo = parcial`:

custo_conhecido_parcial =
soma dos custos totais somente das linhas conhecidas

`custo_dos_produtos` e `custo_conhecido_parcial` são grandezas diferentes e não podem ser substituídas uma pela outra.

Também existe inconsistência quando:

custo_total_linha
≠
custo_unitario_historico × quantidade

A inconsistência de custo:

- não altera o valor cobrado do cliente;
- não bloqueia a venda;
- impede apresentar custo, lucro bruto estimado ou margem como resultados confiáveis.

### Preservação histórica

Depois da confirmação, devem permanecer preservados:

- estado do custo;
- custo unitário histórico de cada item conhecido;
- quantidade;
- custo total de cada linha conhecida;
- custo dos produtos, quando completo;
- custo conhecido parcial, quando aplicável;
- quantidade de itens ou unidades sem custo;
- valores utilizados no momento da confirmação.

### Arredondamento

1. Receber o custo unitário válido.
2. Arredondar o custo unitário para duas casas.
3. Multiplicar pela quantidade.
4. Arredondar o custo total da linha.
5. Somar os custos totais conhecidos.
6. Arredondar o valor consolidado aplicável.
7. Determinar se o estado é conhecido, parcial ou desconhecido.

Nunca utilizar truncamento.

---

## 10. Lucro bruto estimado

### Definição

Lucro bruto estimado é a diferença entre a receita líquida dos produtos e o custo completo dos produtos utilizados no pedido.

Fórmula oficial:

lucro_bruto_estimado =
receita_liquida - custo_dos_produtos

Com arredondamento:

lucro_bruto_estimado =
arredondar(receita_liquida - custo_dos_produtos, 2)

### Natureza estimada

O termo oficial é:

lucro bruto estimado

O cálculo considera somente:

- receita líquida dos produtos;
- custo completo dos produtos cadastrado pelo restaurante.

Ele não considera automaticamente:

- embalagem;
- recipiente;
- talheres;
- materiais descartáveis;
- comissão de plataforma;
- taxa de cartão;
- impostos;
- salários;
- aluguel;
- energia;
- gás;
- desperdício;
- custo do motoboy;
- despesas administrativas;
- despesas operacionais;
- resultado financeiro da entrega;
- estornos;
- perdas financeiras.

Nunca utilizar a expressão “lucro líquido” para esse resultado.

O valor também não deve ser apresentado como lucro final real do restaurante.

### Condição obrigatória de cálculo

O lucro bruto estimado somente pode ser calculado e apresentado como completo quando:

estado_custo = conhecido

Quando:

estado_custo = parcial

ou:

estado_custo = desconhecido

o sistema:

- não deve calcular lucro parcial e apresentá-lo como completo;
- não deve utilizar custo ausente como zero;
- não deve utilizar `custo_conhecido_parcial` como `custo_dos_produtos`;
- deve informar que o lucro bruto estimado está indisponível;
- pode indicar quais custos estão ausentes;
- não deve bloquear a venda.

### Relação com receita líquida

A base de receita utilizada é exclusivamente:

receita_liquida

Não utilizar:

- subtotal bruto;
- total final;
- valor pago;
- valor recebido em caixa;
- receita líquida acrescida da taxa de entrega.

Fórmula de conferência:

receita_liquida =
lucro_bruto_estimado + custo_dos_produtos

### Relação com taxa de entrega

A taxa de entrega não entra no lucro bruto estimado dos produtos.

A fórmula correta é:

lucro_bruto_estimado =
receita_liquida - custo_dos_produtos

Não utilizar:

lucro_bruto_estimado =
total_final - custo_dos_produtos

O resultado financeiro da entrega será tratado separadamente em regra futura.

### Resultado positivo, zero ou negativo

O resultado pode ser positivo quando:

receita_liquida > custo_dos_produtos

Pode ser igual a zero quando:

receita_liquida = custo_dos_produtos

Pode ser negativo quando:

receita_liquida < custo_dos_produtos

O resultado negativo continua sendo armazenado na própria grandeza:

lucro_bruto_estimado

com valor inferior a zero.

Ele pode ser apresentado ao restaurante com o rótulo:

prejuízo bruto estimado

Porém, não criar uma segunda grandeza ou fórmula independente chamada `prejuizo_bruto_estimado`.

O sistema não deve converter resultado negativo em zero.

### Venda com resultado negativo

Uma venda pode ser confirmada mesmo quando o lucro bruto estimado for negativo.

O sistema pode alertar sobre prejuízo bruto estimado, mas não deve bloquear automaticamente a venda.

A decisão comercial pertence ao restaurante.

O alerta não deve alterar:

- preço;
- desconto;
- quantidade;
- confirmação;
- pagamento.

### Relação com descontos

Os descontos:

- reduzem a receita líquida;
- não reduzem o custo dos produtos;
- podem reduzir o lucro bruto estimado;
- podem zerar o lucro bruto estimado;
- podem produzir resultado negativo.

Exemplo:

Subtotal bruto: R$ 100,00
Desconto total: R$ 30,00
Receita líquida: R$ 70,00
Custo dos produtos: R$ 60,00
Lucro bruto estimado: R$ 10,00

Outro exemplo:

Subtotal bruto: R$ 100,00
Desconto total: R$ 50,00
Receita líquida: R$ 50,00
Custo dos produtos: R$ 60,00
Lucro bruto estimado: -R$ 10,00

### Desconto de 100%

Quando:

receita_liquida = R$ 0,00

e o custo estiver completamente conhecido:

lucro_bruto_estimado =
0 - custo_dos_produtos

Exemplo:

Receita líquida: R$ 0,00
Custo dos produtos: R$ 40,00
Lucro bruto estimado: -R$ 40,00

A taxa de entrega permanece separada e não altera esse resultado.

### Relação com pagamento

O lucro bruto estimado é independente do estado de pagamento.

Portanto:

- pedido não pago pode possuir lucro bruto estimado;
- marcar como pago não altera o resultado;
- desmarcar como pago não recalcula o resultado;
- forma de pagamento não altera o resultado nesta definição;
- troco não altera o resultado.

Lucro bruto estimado e entrada financeira recebida são conceitos diferentes.

Taxas de meios de pagamento serão tratadas separadamente.

### Relação com cancelamento

Depois da confirmação:

- a receita líquida histórica permanece preservada;
- o custo histórico permanece preservado;
- o lucro bruto estimado histórico, quando calculado, deve permanecer preservado;
- cancelar não apaga nem recalcula esses valores;
- pedidos cancelados não entram nos consolidados de vendas válidas;
- os valores permanecem disponíveis para auditoria.

Não são definidos nesta etapa:

- estorno;
- desperdício;
- aproveitamento de ingredientes;
- devolução;
- baixa de estoque;
- perda financeira após a produção.

### Momento de fixação

O lucro bruto estimado deve ser determinado no momento da confirmação, desde que:

estado_custo = conhecido

Depois da confirmação:

- alterações futuras no preço não recalculam o pedido;
- alterações futuras no custo não recalculam o pedido;
- alterações futuras em promoções não recalculam o pedido;
- alterações futuras em combos não recalculam o pedido;
- alterações futuras na taxa de entrega não recalculam o pedido;
- o resultado histórico permanece auditável.

Quando o custo estiver parcial ou desconhecido no momento da confirmação:

- o lucro bruto estimado permanece indisponível;
- cadastrar custos posteriormente não recalcula automaticamente o pedido antigo;
- o estado histórico não deve ser alterado silenciosamente.

### Estados oficiais do resultado

A representação oficial é:

estado_lucro_bruto =
calculado | indisponivel

#### Calculado

O estado será calculado quando:

- `estado_custo = conhecido`;
- a receita líquida for válida;
- o custo dos produtos for válido;
- a fórmula não possuir divergências.

estado_lucro_bruto = calculado

O resultado calculado pode ser positivo, zero ou negativo.

#### Indisponível

O estado será indisponível quando:

- o custo for parcial;
- o custo for desconhecido;
- o custo for inválido;
- a receita líquida for inválida;
- existir inconsistência na fórmula.

estado_lucro_bruto = indisponivel

Não existe estado de lucro bruto “parcialmente calculado” apresentado como resultado completo.

### Inconsistências

Existe inconsistência quando:

lucro_bruto_estimado
≠
receita_liquida - custo_dos_produtos

Também existe inconsistência quando:

- o sistema apresenta lucro bruto estimado com `estado_custo ≠ conhecido`;
- utiliza `custo_conhecido_parcial` como custo total;
- utiliza `total_final` no lugar de `receita_liquida`;
- inclui taxa de entrega na fórmula;
- apresenta resultado indisponível como confiável.

Quando a inconsistência estiver restrita ao cálculo ou à apresentação do lucro bruto estimado:

- não altera o valor cobrado do cliente;
- não bloqueia automaticamente a venda;
- impede apresentar o lucro bruto estimado como confiável;
- deve gerar indicação de erro interno ao restaurante.

Esta regra não elimina os bloqueios já definidos nas etapas anteriores.

Se a origem do problema for uma inconsistência em subtotal bruto, descontos, receita líquida, taxa de entrega ou total final, continuam valendo as regras de bloqueio da confirmação estabelecidas nas respectivas etapas.

### Limites

O lucro bruto estimado:

- pode ser positivo;
- pode ser zero;
- pode ser negativo;
- deve possuir duas casas decimais;
- não pode ser editado diretamente;
- deve ser derivado da receita líquida e do custo completo dos produtos;
- não inclui taxa de entrega;
- não pode ser calculado com custo parcial ou desconhecido.

Não existe limite mínimo igual a zero.

### Preservação histórica

Depois da confirmação, devem permanecer preservados:

- receita líquida utilizada;
- estado do custo;
- custo dos produtos utilizado;
- estado do lucro bruto estimado;
- lucro bruto estimado, quando calculado;
- valores utilizados no momento da confirmação.

### Arredondamento

1. Receber a receita líquida já arredondada.
2. Confirmar que `estado_custo = conhecido`.
3. Receber `custo_dos_produtos` já arredondado.
4. Subtrair o custo dos produtos da receita líquida.
5. Arredondar o resultado para duas casas.
6. Validar a fórmula de conferência.
7. Classificar o resultado como positivo, zero ou negativo.
8. Definir `estado_lucro_bruto = calculado`.

Quando os requisitos não forem atendidos:

estado_lucro_bruto = indisponivel

Nunca utilizar truncamento.

### Casos validados

#### Resultado positivo

Receita líquida: R$ 80,00
Custo dos produtos: R$ 50,00
Lucro bruto estimado: R$ 30,00
Estado: calculado

#### Resultado zero

Receita líquida: R$ 80,00
Custo dos produtos: R$ 80,00
Lucro bruto estimado: R$ 0,00
Estado: calculado

#### Resultado negativo

Receita líquida: R$ 80,00
Custo dos produtos: R$ 90,00
Lucro bruto estimado: -R$ 10,00
Estado: calculado

O resultado pode ser apresentado como prejuízo bruto estimado de R$ 10,00, sem criar uma segunda grandeza financeira.

#### Custo parcial

Receita líquida: R$ 80,00
Custo conhecido parcial: R$ 40,00
Existem itens sem custo.
Lucro bruto estimado: indisponível
Estado: indisponível

Não apresentar lucro de R$ 40,00.

#### Custo desconhecido

Receita líquida: R$ 80,00
Custo dos produtos: desconhecido
Lucro bruto estimado: indisponível
Estado: indisponível

#### Taxa de entrega

Receita líquida: R$ 80,00
Custo dos produtos: R$ 50,00
Taxa de entrega: R$ 8,00
Total final: R$ 88,00
Lucro bruto estimado: R$ 30,00

A taxa de entrega não altera esse indicador.

#### Pedido cancelado

Lucro bruto estimado histórico: R$ 30,00
Pedido posteriormente cancelado.

O valor histórico permanece preservado para auditoria, mas o pedido não entra nos consolidados de vendas válidas.

---

## 11. Margem bruta estimada

### Definição

Margem bruta estimada é o percentual que o lucro bruto estimado representa sobre a receita líquida dos produtos.

Fórmula oficial:

margem_bruta_estimada =
(lucro_bruto_estimado ÷ receita_liquida) × 100

Com arredondamento:

margem_bruta_estimada =
arredondar(
  (lucro_bruto_estimado ÷ receita_liquida) × 100,
  2
)

A margem deve ser armazenada e apresentada como percentual.

### Natureza estimada

O termo oficial é:

margem bruta estimada

Ela considera somente:

- receita líquida dos produtos;
- custo completo dos produtos;
- lucro bruto estimado.

Não considera automaticamente:

- taxa de entrega;
- embalagem;
- comissão de plataforma;
- taxa de cartão;
- impostos;
- salários;
- aluguel;
- energia;
- gás;
- desperdício;
- custo do motoboy;
- despesas administrativas;
- despesas operacionais;
- estornos;
- perdas financeiras.

Nunca chamar esse indicador de margem líquida.

Também não apresentar como rentabilidade final real do restaurante.

### Condições obrigatórias

A margem somente pode ser calculada quando:

estado_lucro_bruto = calculado

e:

receita_liquida > 0

Quando o custo estiver parcial ou desconhecido, o lucro bruto estimado e a margem permanecem indisponíveis.

Quando:

receita_liquida = 0

não realizar divisão por zero.

Nesse caso:

estado_margem_bruta = indisponivel

Não apresentar:

- 0%;
- 100%;
- infinito;
- valor arbitrário.

### Estados oficiais

A representação oficial é:

estado_margem_bruta =
calculada | indisponivel

#### Calculada

A margem será calculada quando:

- `estado_lucro_bruto = calculado`;
- `receita_liquida > 0`;
- os valores da fórmula forem válidos;
- não existir inconsistência.

estado_margem_bruta = calculada

#### Indisponível

A margem será indisponível quando:

- o custo estiver parcial ou desconhecido;
- o lucro bruto estimado estiver indisponível;
- a receita líquida for igual a zero;
- a receita líquida for inválida;
- existir inconsistência na fórmula.

estado_margem_bruta = indisponivel

Não existe estado de margem parcialmente calculada.

### Resultado positivo, zero ou negativo

A margem pode ser positiva quando o lucro bruto estimado for positivo.

Pode ser igual a zero quando:

lucro_bruto_estimado = 0

Pode ser negativa quando:

lucro_bruto_estimado < 0

O sistema não deve converter margem negativa em zero.

Exemplo positivo:

Receita líquida: R$ 80,00
Custo dos produtos: R$ 50,00
Lucro bruto estimado: R$ 30,00
Margem bruta estimada: 37,50%

Exemplo negativo:

Receita líquida: R$ 50,00
Custo dos produtos: R$ 60,00
Lucro bruto estimado: -R$ 10,00
Margem bruta estimada: -20,00%

### Limites conceituais

Como o custo dos produtos conhecido não pode ser negativo:

margem_bruta_estimada ≤ 100%

A margem pode ser negativa.

Não existe limite mínimo igual a zero.

Uma margem superior a 100% indica inconsistência nos valores ou na fórmula.

### Relação com taxa de entrega

A taxa de entrega não entra no numerador nem no denominador.

Utilizar:

receita_liquida

Não utilizar:

total_final

A fórmula não pode ser:

margem_bruta_estimada =
lucro_bruto_estimado ÷ total_final

O resultado financeiro da entrega será tratado separadamente.

### Relação com descontos

Os descontos:

- reduzem a receita líquida;
- não reduzem o custo dos produtos;
- podem reduzir a margem;
- podem zerar a margem;
- podem tornar a margem negativa;
- podem deixar a margem indisponível quando zerarem a receita líquida.

Quando:

receita_liquida = 0

a margem fica indisponível por impossibilidade de divisão.

### Relação com pagamento

A margem é independente do estado de pagamento.

Portanto:

- pedido não pago pode possuir margem calculada;
- marcar como pago não altera a margem;
- desmarcar como pago não recalcula a margem;
- forma de pagamento não altera a margem nesta definição;
- troco não altera a margem.

Margem estimada e entrada financeira recebida são conceitos diferentes.

### Relação com cancelamento

Depois da confirmação:

- a margem calculada permanece preservada historicamente;
- o cancelamento não apaga nem recalcula o valor;
- pedidos cancelados não entram nos consolidados de vendas válidas;
- o resultado permanece disponível para auditoria.

### Momento de fixação

A margem deve ser determinada no momento da confirmação quando todos os requisitos forem válidos.

Depois da confirmação, alterações futuras em:

- preço;
- custo;
- desconto;
- promoção;
- combo;
- taxa de entrega;

não recalculam pedidos antigos.

Quando a margem estiver indisponível no momento da confirmação, cadastrar custos posteriormente não recalcula automaticamente o pedido antigo.

### Inconsistências

Existe inconsistência quando:

margem_bruta_estimada
≠
(lucro_bruto_estimado ÷ receita_liquida) × 100

Também existe inconsistência quando:

- existe cálculo com receita líquida igual a zero;
- é utilizado `total_final` no denominador;
- a taxa de entrega é incluída;
- é utilizado lucro parcial;
- margem indisponível é apresentada como calculada;
- margem superior a 100% é apresentada com custos não negativos.

Quando a inconsistência estiver restrita ao indicador de margem:

- não altera o valor cobrado;
- não bloqueia automaticamente a venda;
- impede apresentar a margem como confiável;
- deve gerar indicação interna ao restaurante.

Esta regra não elimina bloqueios já definidos em etapas anteriores.

### Preservação histórica

Depois da confirmação, devem permanecer preservados:

- receita líquida utilizada;
- estado do custo;
- custo dos produtos utilizado;
- lucro bruto estimado utilizado;
- estado da margem bruta;
- margem bruta estimada, quando calculada;
- valores utilizados no momento da confirmação.

### Arredondamento

1. Receber a receita líquida já arredondada.
2. Confirmar que `estado_lucro_bruto = calculado`.
3. Confirmar que `receita_liquida > 0`.
4. Receber o lucro bruto estimado já arredondado.
5. Dividir o lucro bruto estimado pela receita líquida.
6. Multiplicar o resultado por 100.
7. Arredondar para duas casas decimais.
8. Validar a fórmula.
9. Definir `estado_margem_bruta = calculada`.

Quando os requisitos não forem atendidos:

estado_margem_bruta = indisponivel

Nunca utilizar truncamento.

### Casos validados

#### Margem positiva

Receita líquida: R$ 100,00
Custo dos produtos: R$ 60,00
Lucro bruto estimado: R$ 40,00
Margem bruta estimada: 40,00%
Estado: calculada

#### Margem zero

Receita líquida: R$ 100,00
Custo dos produtos: R$ 100,00
Lucro bruto estimado: R$ 0,00
Margem bruta estimada: 0,00%
Estado: calculada

#### Margem negativa

Receita líquida: R$ 100,00
Custo dos produtos: R$ 120,00
Lucro bruto estimado: -R$ 20,00
Margem bruta estimada: -20,00%
Estado: calculada

#### Receita líquida igual a zero

Receita líquida: R$ 0,00
Custo dos produtos: R$ 40,00
Lucro bruto estimado: -R$ 40,00
Margem bruta estimada: indisponível
Estado: indisponível

#### Custo parcial

Receita líquida: R$ 100,00
Estado do custo: parcial
Lucro bruto estimado: indisponível
Margem bruta estimada: indisponível
Estado: indisponível

#### Taxa de entrega

Receita líquida: R$ 100,00
Custo dos produtos: R$ 60,00
Taxa de entrega: R$ 10,00
Total final: R$ 110,00
Lucro bruto estimado: R$ 40,00
Margem bruta estimada: 40,00%

A taxa de entrega não altera a margem dos produtos.

---

## 12. Decisões ainda pendentes

Ainda não estão definidas:

- modalidades de promoção que serão disponibilizadas na interface;
- modalidades de combo que serão disponibilizadas;
- estrutura técnica das promoções e combos;
- modalidades de desconto manual que serão disponibilizadas na interface;
- estrutura técnica do desconto manual;
- rateio do desconto manual entre itens;
- PIN e autorização por perfil para desconto manual;
- formato do campo de motivo do desconto manual;
- implementação técnica do desconto total;
- estrutura de armazenamento dos componentes do desconto total;
- mecanismo de detecção de inconsistências financeiras;
- implementação técnica da receita líquida;
- estrutura de armazenamento da receita líquida;
- validação das equivalências financeiras;
- implementação técnica da taxa de entrega;
- substituição futura do comportamento `coalesce(..., 0)` para entregas;
- validação da taxa no servidor;
- estrutura para gratuidade de frete;
- cálculo por distância, CEP, bairro ou zona;
- regras de estorno ou devolução da taxa;
- definição e implementação completa do total final;
- cancelamento, pagamento, estorno e movimentações financeiras;
- implementação do cadastro de custos;
- estrutura de armazenamento;
- snapshot histórico;
- custo por tamanho ou variação;
- composição de custo para múltiplos sabores;
- proporções e ingredientes compartilhados;
- custo de adicionais;
- outros custos diretos;
- alertas de custo ausente ou inválido;
- implementação técnica do lucro bruto estimado;
- estrutura de armazenamento do lucro bruto estimado;
- armazenamento de `estado_lucro_bruto`;
- alertas de resultado negativo;
- relatórios e consolidados;
- tratamento financeiro separado da entrega;
- taxas de meios de pagamento;
- despesas e outros custos diretos;
- implementação técnica da margem bruta estimada;
- armazenamento de `estado_margem_bruta`;
- armazenamento do percentual histórico;
- alertas de margem baixa ou negativa;
- preço original versus preço efetivamente cobrado no schema;
- implementação técnica da ordem de cálculo;
- políticas de brinde ou gratuidade;
- alterações necessárias no banco e frontend.

Nenhum desses pontos deve ser implementado por suposição.
