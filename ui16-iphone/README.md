# UI16 Control — iPhone

Controlador nativo para **Soundcraft Ui16**, feito para ser operado com uma mão durante
o evento. SwiftUI, iOS 17+, retrato, tema escuro.

## Gerar o IPA (é isso que você precisa fazer)

```bash
cd ui16-iphone
DEVELOPMENT_TEAM=SEU_TEAM_ID bash scripts/build-ipa.sh
```

Resultado: `ui16-iphone/build/UI16-Control.ipa`

Para descobrir o Team ID: Xcode → Settings → Accounts → sua conta, ou
[developer.apple.com/account](https://developer.apple.com/account) em *Membership details*.

Ou abra no Xcode e use Product → Archive:

```bash
open ui16-iphone/app/UI16Control.xcodeproj
```

No Xcode, selecione o target **UI16Control** → aba *Signing & Capabilities* → marque
*Automatically manage signing* e escolha seu Team. Depois é só Archive → Distribute App.

## Instalar no iPhone

1. Conecte o iPhone no Mac.
2. Xcode → Window → *Devices and Simulators*.
3. Arraste o `.ipa` para a lista *Installed Apps* (ou use Apple Configurator).
4. No iPhone: Ajustes → Geral → *VPN e Gerenciamento de Dispositivo* → confie no seu
   certificado de desenvolvedor.

Na primeira execução o iOS pede permissão de **rede local** — é obrigatório aceitar,
senão o app não enxerga a mesa.

## Conectar na mesa

1. iPhone e Ui16 na **mesma rede Wi-Fi**.
2. Abra o app → ícone de engrenagem.
3. Digite o IP da mesa, ou toque em um dos endereços padrão:
   - `10.10.2.1` — Wi-Fi da própria Ui16
   - `10.10.1.1` — alternativo
   - `192.168.1.1` — rede cabeada/DHCP típica

O IP também aparece no painel da própria mesa. Aceita `ip:porta` (ex.: `10.10.2.1:80`).

## Dois modos no mesmo app

A navegação inferior tem cinco destinos: **PAREDÃO · PLAYER · BIBLIOTECA · EQ · UI16**.
O controlador técnico da Ui16 continua inteiro na aba UI16 — o Modo Paredão foi somado,
não substituiu nada. **A música não para ao trocar de aba**, inclusive ao entrar na Ui16.

### Modo Paredão

Player + biblioteca + playlist + EQ + phase + master, para operar o som do evento pelo
iPhone. Detalhes, decisões e limitações em [`docs/paredao.md`](docs/paredao.md).

Onde cada coisa é processada:

- **EQ de 5 bandas: no iPhone**, não na mesa (os endereços de EQ da Ui16 não são
  confirmados — o app não finge que a mesa processa).
- **Master, DIM, solo, fone e VU: na Ui16.**
- **Phase da mesa:** o app **descobre o endereço real no estado que a Ui16 envia**. Enquanto
  não aparecer, não transmite nada e diz isso na tela.

Formatos: MP3, WAV, AIFF, M4A/AAC, ALAC, CAF e FLAC. As músicas ficam onde estão —
importe uma pasta pelo Files e o app guarda um bookmark, sem copiar nada.

### Modo UI16 (controlador técnico)

| Aba | O que faz |
|---|---|
| **MIXER** | Régua dos 16 canais com VU e mute individual, fader grande do canal selecionado, MUTE/SOLO, master com VU estéreo |
| **CANAL** | Preamp (ganho em dB, phantom 48V), pan, sends AUX 1–6 e FX 1–4 com pre/post, e todos os parâmetros de processamento que a mesa reportar |
| **AUX/FX** | Barramentos AUX, FX e SUB com fader, mute e meter |
| **SHOWS** | Cenas: shows, snapshots e cues salvos na mesa, com confirmação antes de carregar |
| **DIAG** | Contadores ao vivo, todos os VU (pre/post/pós-fader, estéreo, aux, fx, master) e busca em todas as chaves recebidas |

Decisões de operação ao vivo:

- **Fader com arrasto relativo** — encostar no fader não faz o nível pular para o dedo.
- **Mute por canal na régua**, sem precisar selecionar o canal antes.
- **Perda de conexão em faixa vermelha**, não em detalhe sutil.
- **Escritas contínuas agrupadas** (janela de 40 ms) com valor final garantido, para não
  inundar o Wi-Fi durante um arrasto.
- **Haptics** confirmam cada comando quando você não está olhando a tela.

## Desenvolvimento

```bash
bash scripts/test.sh              # testes das bibliotecas (172 testes)
bash scripts/build.sh             # compila para simulador
bash scripts/build.sh device      # compila para iPhone
bash scripts/archive.sh           # archive (sem assinar se não houver team)
bash scripts/build-ipa.sh         # IPA assinado
```

### Testar sem a mesa

Há um mock que fala o protocolo real da Ui16:

```bash
python3 tools/mock-ui16.py --port 8080
```

Ele envia estado completo, VU a 20 Hz e imprime cada comando que o app escreve — útil para
conferir endereços. No simulador, aponte o app para `127.0.0.1:8080`; num iPhone real,
use o IP do seu Mac.

### Estrutura

```
Sources/UI16Controller/   biblioteca pura (protocolo + estado), sem SwiftUI — testável no CI
app/UI16Control/          app SwiftUI
app/UI16Control.xcodeproj projeto Xcode
Tests/                    testes da biblioteca
tools/mock-ui16.py        mesa simulada
docs/protocol.md          protocolo: o que está confirmado e o que falta
```

## Protocolo

O app fala o protocolo real da Ui Series: WebSocket em `ws://<ip>`, frames `3:::`,
keepalive `ALIVE`, estado em `SETD` (números) e `SETS` (texto), VU em `VU2` binário.

**Importante:** a Ui16 não tem 16 canais mono — são 12 entradas mono (`i`), 2 de linha
(`l`) e 2 players (`p`), além de 4 FX, 4 subs e 6 AUX.

Cada comando usado, sua fonte de confirmação e as pendências estão em
[`docs/protocol.md`](docs/protocol.md).

## Limitações honestas

- **EQ, Gate, Compressor, Phase e HPF** não têm endereço de escrita publicamente
  confirmado. O app **não inventa** comandos: ele lista os parâmetros reais que a mesa
  reportar e permite editá-los pelo endereço verdadeiro. Ao conectar na Ui16, esses
  controles aparecem sozinhos.
- **Cenas/presets**: carregar shows, snapshots e cues está implementado e validado contra
  o mock. Salvar/sobrescrever existe na biblioteca, mas ainda não tem botão na interface,
  para evitar sobrescrever um show por engano durante o evento.
- Tudo foi validado contra o mock e o simulador. **A confirmação final de cada escrita
  depende da Ui16 física.**

## Gerar IPA pelo GitHub Actions (opcional)

O workflow `.github/workflows/ui16-ios.yml` testa a biblioteca e compila o app a cada
push. Para gerar IPA assinado (**Actions → UI16 iPhone Build → Run workflow**), crie os
secrets:

- `DEVELOPMENT_TEAM` — Team ID
- `PROVISIONING_PROFILE_SPECIFIER` — nome do profile para `com.marqueslab.ui16control`
- `APPLE_CERTIFICATE_BASE64` — `.p12` em Base64
- `APPLE_CERTIFICATE_PASSWORD` — senha do `.p12`
- `APPLE_PROVISIONING_PROFILE_BASE64` — `.mobileprovision` em Base64

```bash
base64 -i AppleDevelopment.p12 | pbcopy
base64 -i UI16Control.mobileprovision | pbcopy
```

Nunca coloque certificado, senha ou profile no código.
