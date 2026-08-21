# UX — Marques Lab Camera Monitor

## Direção visual

Interface inspirada em monitores profissionais de produção, mas simplificada para operação de evento. O vídeo é o elemento dominante. Controles aparecem somente quando agregam decisão ou ação.

### Hierarquia

1. Preview
2. Estado da câmera
3. Nome da câmera
4. Rec/Stop
5. Informações técnicas secundárias

## Layout Quad View

```text
┌─────────────────────────────────────────────────────────────┐
│ CAMERA MONITOR                              Wi‑Fi  ● ONLINE  │
├───────────────────────────────┬─────────────────────────────┤
│ HERO 10                 ● REC │ GO PRO MAX          STANDBY │
│                               │                             │
│          LIVE PREVIEW         │         LIVE PREVIEW        │
│                               │                             │
│ 00:18:42                      │ —                           │
├───────────────────────────────┼─────────────────────────────┤
│ IPHONE 17 PRO MAX       ● REC │ IPHONE 16 PRO MAX    ● REC │
│                               │                             │
│          LIVE PREVIEW         │         LIVE PREVIEW        │
│                               │                             │
│ 00:18:40                      │ 00:18:39                    │
└───────────────────────────────┴─────────────────────────────┘
```

## Layout Single View

```text
┌─────────────────────────────────────────────────────────────┐
│ ← QUAD VIEW     HERO 10                  ● REC 00:18:42     │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│                                                             │
│                      LIVE PREVIEW                           │
│                                                             │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│ HERO10       MAX        IPHONE 17       IPHONE 16           │
│  preview     preview       preview         preview          │
├───────────────────────────────┬─────────────────────────────┤
│                               │                             │
│          ● PARAR              │        + INICIAR            │
│                               │                             │
└───────────────────────────────┴─────────────────────────────┘
```

## Interações

### Toque em uma câmera

Abre Single View.

### Toque novamente no preview

Mostra/oculta controles de operação, mantendo o vídeo limpo por padrão.

### Botão GRAVAR

O botão entra em estado de comando. A interface mostra `Aguardando câmera...` até receber confirmação.

### Botão PARAR

Mesma regra: o estado só vira STANDBY após confirmação.

### Long press

Reservado para funções destrutivas ou configurações futuras. REC/STOP não deve depender de long press.

## Feedback de estados

### REC

Indicador vermelho discreto porém inequívoco, contador monoespaçado e animação de pulsação curta. A animação deve pausar ou reduzir quando necessário.

### STANDBY

Estado neutro, sem distração visual.

### CONNECTING

Mini estado de atividade com mensagem curta.

### OFFLINE

Preview substituído por uma superfície limpa informando que a câmera perdeu conexão, com ação RECONECTAR.

### ERROR

Mensagem objetiva e acionável. Evitar stack traces ou texto técnico para o operador.

## Princípios de acessibilidade

- contraste adequado;
- alvos de toque grandes para operação em tablet;
- sem depender apenas de cor para estados;
- textos curtos e legíveis à distância;
- suporte a redução de movimento;
- feedback de ação por texto/ícone além de cor.

## Navegação

Evitar bottom navigation complexa. O app possui essencialmente dois modos:

- **Monitor** — Quad View / Single View
- **Configuração** — rede, nomes, protocolo e diagnóstico

## Configuração

A configuração nunca deve esconder o estado das câmeras. O operador deve conseguir retornar ao monitor com um toque.

## Microcopy

Preferir:

- `GRAVANDO`
- `PRONTA`
- `CONECTANDO`
- `OFFLINE`
- `REC INICIADO`
- `GRAVAÇÃO PARADA`
- `RECONECTAR`
- `COMANDO NÃO CONFIRMADO`

Evitar:

- mensagens técnicas longas;
- abreviações sem contexto;
- alertas redundantes.
