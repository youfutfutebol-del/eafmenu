-- BUG DE SCHEMA: promocao_etapa_itens.opcao_tamanho_id apontava (FK) pra produto_precos(id),
-- mas em todo o resto do sistema esse campo é tratado como um opcoes_tamanho.id:
--   - assets/js/promocoes.js monta o <select> de "Tamanho" no painel usando
--     produto_precos.opcao_tamanho_id como valor (ou seja, um id de opcoes_tamanho).
--   - adicionar_pacote_promocao_pedido() compara
--     pei.opcao_tamanho_id = (v_etapa->>'opcao_tamanho_id')::uuid contra o valor que o
--     cliente manda, que é sempre um opcoes_tamanho.id (detalheTamanhoSelecionadoId em
--     cliente/index.html).
--   - produto_precos.opcao_tamanho_id (mesmo nome de coluna, tabela diferente) também
--     referencia opcoes_tamanho.
-- Com a FK errada, qualquer tentativa de travar uma etapa num tamanho específico falhava
-- na hora de salvar (violação de FK), tanto no painel quanto em qualquer inserção direta.
-- Confirmado antes de aplicar: das 24 linhas existentes em promocao_etapa_itens, nenhuma
-- tem opcao_tamanho_id preenchido — o recurso nunca foi exercitado, então a correção não
-- migra nenhum dado, só troca o alvo da FK.

alter table public.promocao_etapa_itens
  drop constraint promocao_etapa_itens_opcao_tamanho_id_fkey;

alter table public.promocao_etapa_itens
  add constraint promocao_etapa_itens_opcao_tamanho_id_fkey
  foreign key (opcao_tamanho_id) references public.opcoes_tamanho(id) on delete cascade;
