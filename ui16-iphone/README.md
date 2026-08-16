# UI16 Control — iPhone

Controlador nativo para **Soundcraft Ui16**, otimizado para iPhone em modo retrato.

## Entregue

- SwiftUI / iOS 17+
- WebSocket local `ws://<IP>`
- Keepalive `ALIVE` a cada 1 s
- Reconexão automática
- Faders Master + 16 entradas
- Mute / Solo / Gain / Pan / Phantom / Phase / HPF
- AUX 1–4
- AUX / FX / Master dashboard
- Estrutura para 4 FX, BPM e 6 parâmetros por FX
- Decodificação do stream `VU2` em Base64
- VU pré, pós e pós-fader para Input/Player/Line
- VU estéreo para FX/Sub/Master
- VU para AUX
- Inspetor de métricas: todas as mensagens `SETD` recebidas ficam preservadas, inclusive parâmetros ainda sem controle dedicado na UI
- Permissão de rede local do iOS

## Protocolo

A Ui Series usa WebSocket local para comunicação. O estado é recebido em mensagens `SETD^key^value`; o stream de VU usa `VU2^<base64>`.

## Abrir no Xcode

1. Clone este repositório.
2. Abra `ui16-iphone/Package.swift` no Xcode.
3. Selecione o scheme **UI16Phone**.
4. Selecione um iPhone físico com iOS 17+.
5. Configure sua assinatura Apple Development.
6. Execute.
7. Conecte o iPhone à mesma rede Wi‑Fi da Ui16.
8. O IP inicial é `10.10.2.1`, podendo ser alterado em ⚙️.

## Validação física

O código está preparado para ser testado na Ui16 física. A confirmação final de cada comando de escrita depende da resposta da mesa real; comandos ainda não validados em hardware não devem ser tratados como comprovados.
