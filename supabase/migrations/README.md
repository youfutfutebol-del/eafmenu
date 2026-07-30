# Histórico de migrations

Este diretório contém o histórico completo de migrations do projeto Supabase
`vtxugkwazghjgbjxkjal`, uma por versão, no formato padrão do Supabase CLI:

```
supabase/migrations/{version}_{name}.sql
```

## Origem dos arquivos

A maior parte das migrations listadas aqui foi aplicada diretamente no projeto
ao longo do tempo, sem passar por um arquivo versionado em git. Nesta tarefa,
o conteúdo de cada migration ausente foi recuperado, somente leitura, a partir
da tabela interna do Supabase `supabase_migrations.schema_migrations` (colunas
`version`, `name`, `statements`) e gravado em disco exatamente como estava
registrado ali — sem reformatação, sem comentários adicionados e sem qualquer
alteração de conteúdo histórico.

Cada arquivo foi conferido byte a byte (checksum MD5) contra o conteúdo da
tabela `schema_migrations` antes de ser adicionado ao índice do git.

## O que este commit fez

- Removeu o único arquivo com timestamp incorreto
  (`20260726160000_expiracao_diaria_sessao_cliente_a_aditivo.sql`).
- Manteve o arquivo correspondente com o timestamp correto
  (`20260727053615_expiracao_diaria_sessao_cliente_a_aditivo.sql`).
- Adicionou os demais arquivos faltantes, totalizando 88 migrations versionadas,
  uma para cada migration já aplicada ao banco.

## O que este commit não fez

- Não executou `supabase db push`, `migration repair`, `reset` ou qualquer
  comando que altere o banco de dados.
- Não alterou nenhum conteúdo histórico das migrations recuperadas.
- Não fez merge para a branch principal.
