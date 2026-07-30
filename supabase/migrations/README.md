# Migrations do Supabase

O histórico aplicado no Supabase é a fonte de verdade deste diretório.

- Todo SQL aplicado deve ser versionado no mesmo dia.
- Migrations já aplicadas não devem ser editadas.
- Correções futuras devem ser feitas em uma nova migration.
- `supabase db push`, `migration repair` e `reset` exigem autorização explícita.
- Cada arquivo deve seguir o padrão `<versão>_<nome>.sql`.
