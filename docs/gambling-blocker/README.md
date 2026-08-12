# Gambling Blocker — Fundação iOS

## Objetivo
Construir um bloqueador para iPhone que impeça, por padrão, acesso a conteúdo de jogos de azar e apostas.

## Estratégia de bloqueio

1. Catálogo de domínios e padrões de URL conhecidos.
2. Categorias de conteúdo de azar/apostas.
3. Palavras-chave em host, URL e regras de classificação quando disponíveis.
4. Bloqueio de aplicativos selecionados usando as APIs de Screen Time quando permitido pelo entitlement e modelo de distribuição.
5. Camadas de rede usando Network Extension quando elegível.
6. Atualização do catálogo sem depender apenas de uma lista embarcada no aplicativo.

## Categorias prioritárias

- sportsbook / apostas esportivas
- casino / cassino
- live casino
- slots
- roleta
- blackjack
- poker com dinheiro real
- bingo de dinheiro real
- crash / cassino instantâneo
- loterias e sorteios com aposta
- afiliados e páginas de redirecionamento de apostas
- páginas promocionais de casas de apostas

## Regra padrão

Modo estrito: bloquear por padrão tudo que for classificado pelo mecanismo como conteúdo de azar. Exceções não fazem parte da V1 inicial.

## Limitação importante do iOS

A cobertura e o modelo de distribuição dependem dos entitlements da Apple. Family Controls fornece acesso às APIs de controle do Screen Time, e Network Extension fornece mecanismos de filtro de conteúdo; alguns tipos de content filter possuem restrições de distribuição e supervisão. A implementação precisa ser validada no dispositivo-alvo e no perfil de distribuição antes de prometer bloqueio absoluto.
