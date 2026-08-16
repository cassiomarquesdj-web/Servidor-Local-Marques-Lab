# UI16 Control — arquitetura

## Camadas

```
app/UI16Control/            SwiftUI — só apresentação e gestos
  ├─ Design/                tema e controles reutilizáveis (Fader, MeterBar, ConsoleButton)
  └─ Views/                 Mixer, Canal, AUX/FX, Diagnóstico, Conexão

Sources/UI16Controller/     biblioteca pura — sem SwiftUI, sem UIKit
  ├─ Protocol/              endereços, mensagens, curva de dB, decodificador VU2
  ├─ State/                 estado observável, coalescência de escritas
  └─ Transport/             WebSocket, keepalive, reconexão
```

A separação existe por um motivo prático: a biblioteca compila e roda testes no macOS e no
CI, sem simulador. Toda a lógica de protocolo é testável (42 testes) sem abrir o Xcode.

## Transporte (`UI16Connection`)

`actor` sobre `URLSessionWebSocketTask`.

- Endpoint `ws://<host>:<porta>`; aceita `ip:porta` na string do host.
- Payloads de saída embrulhados em `3:::`.
- Keepalive `ALIVE` a cada 1 s — sem isso a mesa derruba a conexão.
- Frames de entrada podem trazer várias mensagens separadas por `\n`; são divididas antes
  de chegar ao estado.
- O estado de conexão vem do ciclo de vida real do socket (`URLSessionWebSocketDelegate`
  `didOpen`/`didClose`), não de suposição — "conectado" significa socket aberto.
- Reconexão automática com atraso, cancelada quando a desconexão é intencional.

## Estado (`UI16Store`)

`@MainActor`, `ObservableObject`. Duas camadas propositalmente:

1. **Tipada** — `master` e `strips` com os campos que a UI usa (nível, mute, solo, pan,
   ganho, phantom, nome, sends).
2. **Bruta** — `raw: [String: RawValue]` com **toda** chave `SETD`/`SETS` recebida.

A camada bruta é o que permite a regra do projeto: nunca descartar um parâmetro só porque
ainda não existe tela para ele. A aba CANAL e o diagnóstico leem dela por prefixo.

VU chega em `VU2^<base64>`, é decodificado para `VUFrame` tipado e substitui o quadro
anterior (não acumula — é dado instantâneo a ~20 Hz).

## Escrita de comandos

- **Contínuos** (fader, ganho, pan, sends) passam por `CommandThrottle`: agrupados por
  chave numa janela de 40 ms, com escrita final garantida e supressão de valores
  repetidos. Um arrasto de 12 eventos vira ~4 escritas.
- **Discretos** (mute, solo, phantom, pre/post, nomes) são enviados na hora, sem atraso.

A UI atualiza o estado local imediatamente (otimista) e a mesa confirma pelo eco — o mesmo
comportamento da interface web da própria Ui.

## Decisões de interface para uso ao vivo

- **Retrato apenas.** Uma mão, no escuro, em pé.
- **Fader com arrasto relativo.** Um toque acidental não joga o canal para o topo.
- **Mute acessível sem selecionar o canal** — botão dedicado por canal na régua.
- **VU sempre visível** onde importa: dentro do fader, na régua e no cabeçalho (master).
- **Perda de conexão em faixa vermelha** ocupando a largura da tela.
- **Alvos de toque** de 44 pt no mínimo; 56 pt nos botões críticos.
- **Haptics** em cada comando, para confirmar sem olhar.

## Testes

`swift test` cobre: parsing e codificação de mensagens, endereços da Ui16, curva de dB
(ida e volta), decodificação de VU2, aplicação de estado, parsing de host/porta e a
coalescência de escritas (com relógio injetado, sem depender de tempo real).

O que não dá para cobrir em teste unitário é validado contra `tools/mock-ui16.py`, que
fala o protocolo real.
