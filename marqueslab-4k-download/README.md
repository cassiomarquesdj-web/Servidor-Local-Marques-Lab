# Marques Lab 4K Download

Gerenciador de downloads de mídia para macOS: fila inteligente, 4K, MP4 e MP3
320 kbps, empacotado como aplicativo nativo com FFmpeg embarcado.

O usuário final baixa o DMG, arrasta para `Applications` e abre. **Sem Terminal,
sem Python, sem FFmpeg, sem instalar dependência nenhuma.**

## O aplicativo

- **Fila real** com estados explícitos (na fila, baixando, concluído, cancelado,
  falhou), progresso, velocidade, ETA e tamanho por item.
- **Várias URLs de uma vez** — cole uma por linha ou arraste links para a janela.
- **Análise da fonte** em segundo plano: título, canal, duração, maior altura
  disponível e número de itens de playlist, sem travar a interface.
- **MP4** até 2160p/1440p/1080p/720p ou a melhor qualidade disponível.
- **Perfil compatível com Premiere Pro e After Effects** (H.264 + AAC), ligado por
  padrão. O YouTube entrega AV1/Opus por padrão, que os dois editores recusam; até
  1080p o arquivo chega pronto, sem reconversão. Acima disso o FFmpeg embarcado
  converte usando o encoder de hardware da Apple, com progresso na fila.
- **MP3 320 kbps** com metadados, extraído pelo FFmpeg embarcado.
- **Cancelar, tentar novamente, remover selecionados e limpar concluídos** sem
  corromper a fila em andamento.
- **Duplo clique revela o arquivo no Finder**; itens com erro mostram o motivo.
- **Histórico persistente** e pasta de saída lembrada entre sessões.

O aplicativo não captura credenciais nem cookies e não implementa contorno de
login, paywall ou DRM. Ele se destina a conteúdo que o usuário possui ou tem
autorização para baixar.

## Arquitetura

| Camada | Arquivo | Responsabilidade |
| --- | --- | --- |
| Identidade | `branding.py` | nome, versão, bundle id e requisito de macOS — fonte única |
| Engine | `engine.py` | yt-dlp, seleção de formato, cancelamento, descoberta do FFmpeg |
| Aplicação | `app.py` | fila, threads, estado, histórico e interface |
| Empacotamento | `MarquesLab4KDownload.spec`, `packaging/` | `.app`, assinatura, notarização, DMG, validação |
| Ícone | `tools/make_icon.py`, `assets/AppIcon.icns` | ícone `.icns` gerado e versionado |

A engine é a única camada que conhece yt-dlp e FFmpeg. A interface nunca executa
rede na thread principal.

## Desenvolvimento

```bash
cd marqueslab-4k-download
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements-dev.txt
python -m app
```

### Testes

```bash
pytest -q
```

A suíte inclui **downloads reais**: um clipe é gerado pelo FFmpeg, servido por um
servidor HTTP local e baixado de volta pela engine, inclusive com conversão para
MP3 e teste de cancelamento. Nenhum site de terceiros é acessado.

A suíte também trava o contrato de distribuição: se alguém remover o Hardened
Runtime, a notarização, a validação do Gatekeeper ou tentar publicar um artefato
não assinado, os testes falham.

### Ícone

```bash
python tools/make_icon.py
```

## Build macOS

```bash
# build de engenharia, sem assinatura — não distribuível
MARQUESLAB_ALLOW_HOST_PYTHON=1 packaging/build_app.sh

# pipeline completo de release (exige as credenciais Apple)
packaging/release_macos.sh
```

Etapas do pipeline de release, nesta ordem, com falha dura em qualquer uma:

1. `build_app.sh` — PyInstaller, FFmpeg embarcado, Info.plist, ícone,
   verificação do `LSMinimumSystemVersion` contra o `minos` real dos binários e
   smoke test do bundle.
2. `check_apple_credentials.sh` — exige os Secrets; sem eles o processo para aqui.
3. `sign_app.sh` — assinatura de dentro para fora com Developer ID, Hardened
   Runtime, timestamp seguro e entitlements.
4. `notarize.sh` — notarização do aplicativo e staple do ticket.
5. `make_dmg.sh` — DMG com atalho para `/Applications`, ícone de volume e assinatura.
6. `notarize.sh` — notarização e staple do DMG.
7. `verify_release.sh` — `codesign --verify`, `spctl --assess`,
   `xcrun stapler validate` e execução real do aplicativo a partir do DMG montado.

## Distribuição

O passo a passo das credenciais Apple está em [DISTRIBUICAO.md](DISTRIBUICAO.md).
O estado atual e o que foi de fato validado estão em [DIAGNOSTICO.md](DIAGNOSTICO.md).

## Requisitos do usuário final

- macOS 12 Monterey ou superior (imposto pelas bibliotecas Qt embarcadas).
- Apple Silicon ou Intel.
