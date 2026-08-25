# Marques Lab — Music Radar

Radar de tendências musicais por artista, com coleta por fonte, histórico temporal e índice de tendência.

## Objetivo

Informar quais músicas de um artista estão com maior procura e crescimento sem apresentar métricas inventadas.

## Arquitetura inicial

- `apps/web`: interface do radar.
- `services/api`: API de consulta e agregação.
- `services/collectors`: conectores por fonte (Google Trends, YouTube e futuras fontes).
- `packages/domain`: modelos e regras de negócio.
- `packages/scoring`: cálculo determinístico do índice de tendência.
- `docs`: especificações, limites de dados e roadmap.

## Regra de confiabilidade

Cada métrica deve possuir fonte, timestamp, período, região e status de disponibilidade. Quando uma fonte não fornecer um dado, o sistema deve marcar como indisponível; nunca preencher com estimativa apresentada como fato.

## Status

Estrutura base criada. Próximos módulos devem ser implementados de forma incremental e testável.
