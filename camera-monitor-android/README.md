# Marques Lab Camera Monitor

Aplicativo Android para tablet dedicado a **monitorar e controlar remotamente quatro câmeras via Wi‑Fi local**:

- GoPro HERO 10
- GoPro MAX
- iPhone 17 Pro Max
- iPhone 16 Pro Max

O tablet não grava vídeo. Ele funciona como **monitor + remote controller**: preview ao vivo, estado real de gravação, contador e comandos de iniciar/parar quando suportados pelo protocolo da câmera.

## Objetivo

Criar uma interface de operação ao vivo, moderna, clean e muito rápida de entender de relance durante eventos.

## Princípios de UX

- **Preview primeiro:** o vídeo ocupa a maior área possível.
- **Estado inequívoco:** REC, STANDBY, CONNECTING e OFFLINE sempre visíveis.
- **Ação confirmada:** o app só mostra REC após confirmação do dispositivo.
- **Baixa carga cognitiva:** poucos controles, hierarquia forte e sem menus escondidos para ações críticas.
- **Operação de evento:** botões grandes, feedback imediato, suporte a horizontal e tela sempre ativa.
- **Resiliência:** reconexão automática, timeout explícito e identificação clara de câmera indisponível.

## UX principal

### Quad View

Grade 2x2 com quatro previews. Cada célula mostra:

- nome da câmera;
- preview;
- indicador REC/standby/offline;
- contador quando gravando;
- qualidade/conexão de forma secundária.

### Single View

Uma câmera em tela grande, com três miniaturas para troca rápida.

### Camera Remote

Ações principais:

- iniciar gravação;
- parar gravação;
- solicitar atualização de estado;
- reconectar.

Comandos somente são refletidos na UI após confirmação do dispositivo.

## Estados

```text
OFFLINE       Sem comunicação com a câmera
CONNECTING    Handshake/reconexão em andamento
STANDBY       Câmera conectada e não gravando
REC           Câmera confirmou gravação
ERROR         Câmera conectada, mas reportou erro
UNSUPPORTED   Função ainda não implementada para aquele modelo/protocolo
```

## Design System

Tema base escuro para operação em ambiente de evento.

- fundo quase preto;
- superfícies discretamente elevadas;
- tipografia limpa e legível;
- acento principal usado somente para ações/estados ativos;
- REC usa destaque visual forte, mas sem poluir a interface;
- cantos e espaçamentos consistentes;
- animações curtas e discretas, com respeito a redução de movimento.

## Arquitetura

```text
Presentation (Flutter)
        |
        v
 Camera Domain
        |
        +---- Camera Session Manager
        +---- Camera State Machine
        +---- Preview Pipeline
        +---- Remote Command Pipeline
        |
        v
 Protocol Adapters
   +---------+---------+-----------+
   |         |         |           |
 HERO10    MAX      iPhone17    iPhone16
```

Cada câmera terá um adapter isolado. O app não deve assumir que GoPro e iPhone usam o mesmo protocolo.

## Regra crítica

**Nunca falsificar o estado de REC.**

Ao pressionar GRAVAR:

```text
UI -> comando -> câmera -> confirmação -> REC
```

Ao pressionar PARAR:

```text
UI -> comando -> câmera -> confirmação -> STANDBY
```

## Fases

### Fase 0 — Produto e UX

- arquitetura de navegação;
- design system;
- estados de câmera;
- wireframes de Quad/Single/Remote;
- contratos de domínio.

### Fase 1 — Shell Android

- Flutter;
- landscape-first;
- tela sempre ativa;
- navegação mínima;
- componentes visuais.

### Fase 2 — Preview

- ingestão do stream local;
- sincronização de estado;
- reconexão automática;
- métricas básicas.

### Fase 3 — Remote Control

- REC;
- STOP;
- status real;
- tratamento de erros;
- confirmação de comando.

### Fase 4 — Hardware Validation

Validar separadamente:

1. GoPro HERO 10
2. GoPro MAX
3. iPhone 17 Pro Max
4. iPhone 16 Pro Max

Depois validar quatro streams simultâneos no mesmo Wi‑Fi.

## Importante sobre protocolos

A camada de protocolo permanece desacoplada da interface. Isso permite validar, para cada câmera, quais operações reais estão disponíveis por Wi‑Fi antes de declarar uma função como suportada.

## Pasta do projeto

```text
camera-monitor-android/
├── README.md
├── docs/
│   ├── UX.md
│   ├── ARCHITECTURE.md
│   └── CAMERA-PROTOCOL-MATRIX.md
└── app/
    └── README.md
```

## Status atual

**Fase 0 — especificação e UX:** definida nesta branch.

A implementação de transporte/preview deve acontecer somente após validar os protocolos reais dos quatro equipamentos.