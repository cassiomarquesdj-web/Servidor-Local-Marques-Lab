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
- Script de geração de IPA: `scripts/build-ipa.sh`
- GitHub Actions para build/test e geração manual de IPA assinado

## Gerar IPA no seu Mac

O IPA precisa ser assinado pela Apple. Com Xcode instalado e sua conta Apple configurada no Mac:

```bash
cd ui16-iphone
DEVELOPMENT_TEAM="SEU_TEAM_ID" bash scripts/build-ipa.sh
```

O arquivo será criado em:

`ui16-iphone/build/UI16-Control.ipa`

Para assinatura manual, informe também o nome do provisioning profile:

```bash
DEVELOPMENT_TEAM="SEU_TEAM_ID" PROVISIONING_PROFILE_SPECIFIER="SEU_PROFILE" bash scripts/build-ipa.sh
```

## Gerar IPA pelo GitHub Actions

O workflow `.github/workflows/ui16-ios.yml` tem uma execução manual chamada **ipa**. Para habilitá-la, crie estes GitHub Actions Secrets:

- `DEVELOPMENT_TEAM` — Team ID da Apple Developer
- `PROVISIONING_PROFILE_SPECIFIER` — nome do provisioning profile para `com.marqueslab.ui16control`
- `APPLE_CERTIFICATE_BASE64` — arquivo `.p12` convertido para Base64
- `APPLE_CERTIFICATE_PASSWORD` — senha do `.p12`
- `APPLE_PROVISIONING_PROFILE_BASE64` — arquivo `.mobileprovision` convertido para Base64

Depois, no GitHub: **Actions → UI16 iPhone Build → Run workflow**. O resultado aparece como artifact **UI16-Control-iPhone** contendo `UI16-Control.ipa`.

### Preparar os arquivos Base64 no Mac

```bash
base64 -i AppleDevelopment.p12 | pbcopy
base64 -i UI16Control.mobileprovision | pbcopy
```

Cole cada resultado no Secret correspondente. Nunca coloque certificado, senha ou provisioning profile no código do projeto.

## Instalação no iPhone

Depois de gerar o IPA assinado com perfil de desenvolvimento, ele pode ser instalado no iPhone associado ao perfil usando Xcode/Apple Configurator ou um fluxo de distribuição adequado à sua conta Apple.

## Protocolo

A Ui Series usa WebSocket local para comunicação. O estado é recebido em mensagens `SETD^key^value`; o stream de VU usa `VU2^<base64>`.

## Validação física

O código está preparado para ser testado na Ui16 física. A confirmação final de cada comando de escrita depende da resposta da mesa real; comandos ainda não validados em hardware não devem ser tratados como comprovados.
