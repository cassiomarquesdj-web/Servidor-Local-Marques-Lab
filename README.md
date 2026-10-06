# Servidor Local Marques Lab

Ferramentas locais do Marques Lab que rodam na rede Wi-Fi/LAN, sem depender de internet.

## Projetos neste repositório

### [`marqueslab-4k-download`](marqueslab-4k-download) — Marques Lab 4K Download

Gerenciador de downloads de mídia para **macOS**, distribuído como aplicativo
nativo assinado e notarizado.

- Fila com progresso, velocidade, ETA, cancelamento e nova tentativa
- MP4 até 4K e MP3 320 kbps, com FFmpeg embarcado no aplicativo
- O usuário baixa o DMG, arrasta para `Applications` e abre — sem Terminal,
  sem Python, sem instalar dependências
- Pipeline completo de assinatura Developer ID, notarização Apple, staple,
  validação de Gatekeeper e publicação automática do release

Estado atual e o que falta: [`marqueslab-4k-download/DIAGNOSTICO.md`](marqueslab-4k-download/DIAGNOSTICO.md).

### [`ui16-iphone`](ui16-iphone) — UI16 Control

Aplicativo iPhone nativo para controlar a mesa **Soundcraft Ui16** pela rede local.

- SwiftUI, iOS 17+, retrato, tema escuro, feito para operação ao vivo com uma mão
- 16 fontes de entrada, AUX, FX, subs e master
- VU meters em tempo real (pre, post, pós-fader, estéreo)
- Painel de diagnóstico com todo o estado recebido da mesa
- Protocolo real da Ui Series, documentado em
  [`ui16-iphone/docs/protocol.md`](ui16-iphone/docs/protocol.md)

Para gerar o IPA e instalar no iPhone, veja
[`ui16-iphone/README.md`](ui16-iphone/README.md).

---

Este repositório **não** contém os projetos Marques Drop, Live Console ou AutoCut — cada
um vive em seu próprio repositório.
