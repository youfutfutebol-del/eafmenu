# Migrations do Supabase

O histórico aplicado no Supabase é a fonte de verdade deste diretório.

- Todo SQL aplicado deve ser versionado no mesmo dia.
- Migrations já aplicadas não devem ser editadas.
- Correções futuras devem ser feitas em uma nova migration.
- `supabase db push`, `migration repair` e `reset` exigem autorização explícita.
- Cada arquivo deve seguir o padrão `<versão>_<nome>.sql`.

## Replay em banco vazio

Este diretório reproduz fielmente o histórico aplicado no projeto de produção.
Ele ainda não foi certificado como bootstrap completo para um banco vazio.

Algumas migrations iniciais dependem de objetos que já existiam quando foram
aplicadas. Portanto, não execute `supabase db reset`, `db push` em projeto novo
ou replay integral sem antes criar uma baseline ou validar toda a sequência em
um ambiente descartável.
