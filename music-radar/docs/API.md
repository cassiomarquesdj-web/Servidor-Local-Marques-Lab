# API inicial

## GET /api/v1/search
Busca um artista e retorna identificação normalizada.

## GET /api/v1/artists/:artistId/tracks
Retorna faixas conhecidas para o artista.

## GET /api/v1/artists/:artistId/ranking
Parâmetros: `region`, `days`, `limit`.

Retorna ranking, score, confiança e fatores explicativos.

## GET /api/v1/tracks/:trackId/history
Retorna observações históricas agrupadas por fonte.

## POST /api/v1/runs
Cria uma execução de coleta para um artista/região/período.

## GET /api/v1/runs/:runId
Retorna status, fontes consultadas, erros e observações persistidas.

## Erros

Toda fonte com falha deve aparecer no resultado como erro identificável; a ausência de uma fonte não deve derrubar o ranking das demais.
