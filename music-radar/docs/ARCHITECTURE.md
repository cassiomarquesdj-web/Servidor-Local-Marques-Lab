# Arquitetura

## Camadas

1. Ingestão: coleta dados de provedores externos.
2. Normalização: transforma respostas de provedores em modelos internos comuns.
3. Persistência: armazena observações históricas com fonte e timestamp.
4. Scoring: calcula tendência somente a partir de observações disponíveis.
5. API: expõe artistas, faixas, métricas, ranking e histórico.
6. Web: dashboard do usuário.

## Contrato de uma observação

`source`, `metric`, `artist`, `track`, `value`, `unit`, `region`, `period_start`, `period_end`, `observed_at`, `source_url`, `availability`.

## Princípios

- Não fabricar métricas ausentes.
- Não misturar períodos sem identificação explícita.
- Não comparar métricas incompatíveis como se fossem equivalentes.
- Toda pontuação derivada deve ser explicável e reproduzível.
