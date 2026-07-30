
revoke execute on function _validar_escopo_generico(uuid, text, uuid) from authenticated;
revoke execute on function _validar_produto_tamanho_ativo(uuid, uuid, uuid) from authenticated;
revoke execute on function _opcoes_tamanho_validas_produto(uuid, uuid) from authenticated;
revoke execute on function _produto_tamanho_no_escopo(uuid, uuid, uuid, text) from authenticated;
