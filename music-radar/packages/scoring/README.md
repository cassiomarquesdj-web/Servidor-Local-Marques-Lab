# Scoring

O índice de tendência não é uma métrica de uma plataforma. É um índice derivado.

## Regras do MVP

- Só pontuar sinais cuja observação esteja `available`.
- Cada sinal mantém sua fonte e seu período.
- Crescimento percentual deve comparar períodos equivalentes.
- Métricas incompatíveis não podem ser somadas diretamente sem normalização documentada.
- Uma pontuação deve retornar também os fatores que a produziram.

Exemplo conceitual de saída:

```json
{
  "track": "Exemplo",
  "score": 82.4,
  "confidence": "high",
  "factors": [
    {"source": "google_trends", "factor": "growth", "contribution": 34.1},
    {"source": "youtube", "factor": "velocity", "contribution": 28.3},
    {"source": "youtube", "factor": "views", "contribution": 20.0}
  ]
}
```

Os pesos devem ficar versionados e ser alterados somente com teste e documentação.
