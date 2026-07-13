# Modelo Financeiro do EAF Menu

## Status do documento

- F02.01 — Subtotal bruto: aprovado
- F02.02 — Desconto promocional: aprovado
- F02.03 — Desconto de combo: aprovado conceitualmente
- F02.04 — Desconto manual: aprovado
- F02.05 — Desconto total: aprovado
- F02.06 — Receita líquida: aprovada
- F02.07 — Taxa de entrega: aprovada
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

## 9. Decisões ainda pendentes

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
- custo dos produtos;
- lucro bruto estimado;
- margem bruta;
- preço original versus preço efetivamente cobrado no schema;
- implementação técnica da ordem de cálculo;
- políticas de brinde ou gratuidade;
- alterações necessárias no banco e frontend.

Nenhum desses pontos deve ser implementado por suposição.
