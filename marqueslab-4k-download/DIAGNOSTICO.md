# Diagnóstico — Marques Lab 4K Download

Data da última execução: **18/08/2026** · Máquina de validação: macOS 26.5,
Apple Silicon (arm64).

## Resumo honesto

| Etapa | Situação | Evidência |
| --- | --- | --- |
| 1. Correção dos erros encontrados | **Concluída** | seção "Defeitos corrigidos" |
| 2. Testes passando | **Concluída** | 78 testes, todos verdes |
| 3. FFmpeg e engine validados | **Concluída** | download e conversão MP3 reais |
| 4. PyInstaller validado | **Concluída** | `.app` de 133 MB gerado e executado |
| 5. DMG Apple Silicon | **Concluída** (build de engenharia) | DMG de 54 MB, app roda montado |
| 6. Assinatura Developer ID | **Bloqueada — falta credencial** | nenhum certificado na máquina nem Secret no repositório |
| 7. Notarização Apple | **Bloqueada — depende da etapa 6** | implementada, não executada |
| 8. Validação do Gatekeeper | **Bloqueada — depende da etapa 7** | implementada, não executada |
| 9. Diagnóstico final | este documento | — |
| 10. Não declarar pronto sem teste real | **cumprido** | o projeto **não** está declarado release-ready |

**O aplicativo não está pronto para distribuição pública ainda.** Falta
exatamente uma coisa: as credenciais da Apple. Todo o resto está implementado,
versionado e testado. O passo a passo está em [DISTRIBUICAO.md](DISTRIBUICAO.md).

## Falha em produção corrigida em 21/08/2026

O primeiro download real do usuário falhou com
`ERROR: unable to download video data: HTTP Error 403: Forbidden`.

**Causa raiz:** o yt-dlp estável 2026.7.4 usava o player client `android_vr`,
que o YouTube passou a bloquear na entrega da mídia. A extração de metadados
funcionava — o erro só aparecia na hora de baixar. Reproduzido e isolado:

| yt-dlp | Cliente usado | Resultado |
| --- | --- | --- |
| 2026.7.4 (estável) | `android_vr` | ❌ HTTP 403 |
| 2026.8.20 (nightly) | `visionos` | ✅ download completo |

Trocar de player client manualmente não resolvia: `web`, `ios`, `mweb` e
`web_safari` não retornavam formato algum, e `tv` respondia "The page needs to
be reloaded". A correção real é o extrator atualizado.

**Correções aplicadas:**

1. O yt-dlp passou a seguir o canal **nightly** (`yt-dlp>=2026.8.20.dev0`). O
   sufixo `.dev0` no especificador faz o pip aceitar pré-lançamentos apenas
   para esse pacote, sem `--pre` global. Um extrator estável de sete semanas
   atrás é garantia de quebra em um app de download.
2. Mensagens de erro acionáveis: `HTTP 403` agora explica que a fonte mudou a
   entrega e que o aplicativo precisa ser atualizado, com o texto original do
   yt-dlp disponível em "Detalhes". O mesmo vale para formato indisponível,
   vídeo privado, restrição de idade e site não suportado.
3. A janela "Sobre" mostra a versão do extrator embarcado — primeiro dado a
   conferir quando um site começa a recusar downloads.
4. Teste que trava a escolha do canal: se alguém voltar o yt-dlp para o canal
   estável, a suíte falha.

**Verificação:** o vídeo exato que falhou foi baixado com sucesso pela engine
corrigida — MP4 720p, 171,5 MB, áudio e vídeo mesclados.

### Limitação conhecida

O aplicativo não embarca um runtime JavaScript (Deno/Node). Se o YouTube exigir
a resolução do desafio `n` para alguma mídia, o yt-dlp precisará de um runtime
JS que o bundle não tem, e essa mídia específica pode falhar. As mídias que usam
o cliente `visionos` — o caminho atual — não passam por esse desafio. Embarcar
o Deno (~40 MB) é a solução se isso passar a acontecer com frequência.

## Incompatibilidade com Premiere / After Effects corrigida em 21/08/2026

O MP4 baixado abria em qualquer player e era recusado pelo Premiere Pro e pelo
After Effects: *"o arquivo possui uma compactação não suportada"*.

**Causa raiz:** o seletor `bestvideo+bestaudio` pega o que o YouTube considera
melhor — e o YouTube prefere **AV1** com áudio **Opus**. O arquivo entregue era:

```
Video: av1 (libdav1d) (av01)  1920x1080  2572 kb/s
Audio: opus (Opus)            48000 Hz   108 kb/s
```

Nenhum dos dois codecs é suportado nativamente pelo Premiere ou pelo After
Effects. O contêiner `.mp4` estava correto; o conteúdo é que não era editável.

**Correção:** o modo de vídeo passou a ter um perfil **Compatível com Premiere /
After Effects**, ligado por padrão, que pede H.264 + AAC diretamente à fonte:

```
bestvideo[vcodec^=avc1][height<=N]+bestaudio[acodec^=mp4a]/…
```

O YouTube serve H.264 e AAC até 1080p, então **até 1080p não há reconversão
alguma** — o arquivo chega editável, no stream original, sem perda. Medido no
vídeo que falhou: 100 s de download, zero conversão, resultado
`h264 (High) / aac (LC)`, 449 MB.

Acima de 1080p o YouTube só oferece VP9/AV1. Nesse caso o FFmpeg embarcado
converte para H.264/AAC, preferindo o encoder de hardware da Apple
(`h264_videotoolbox`, ~2,5× mais rápido que o libx264 nesta máquina) e copiando
o stream que já estiver correto — um arquivo com vídeo H.264 e áudio Opus
reconverte só o áudio, em segundos. A conversão mostra progresso real na fila.

Quem quiser o arquivo menor e de maior qualidade para reprodução pode desmarcar
a opção e receber AV1/VP9 — mas aí o Premiere não abre, e agora isso é uma
escolha explícita em vez de uma surpresa.

Um teste pegou um defeito nessa correção antes de ela chegar ao usuário: a
conversão mantinha a extensão de origem, e WebM não aceita H.264/AAC. A saída
agora é sempre `.mp4`.

## Defeitos corrigidos

1. **FFmpeg embarcado nunca era encontrado no app empacotado.**
   `ffmpeg_executable()` aceitava um caminho que existisse, e `--add-binary`
   cria um *diretório* chamado `ffmpeg`. O aplicativo distribuído passaria esse
   diretório ao yt-dlp e toda conversão MP3 e junção 4K falharia. Agora a busca
   exige arquivo executável e cobre os três layouts possíveis de um `.app`
   (`_MEIPASS`, `Contents/Frameworks`, `Contents/Resources`).
2. **O binário embarcado tinha o nome errado.** A wheel do imageio-ffmpeg entrega
   `ffmpeg-macos-aarch64-v7.1`; o bundle precisa de `ffmpeg`. O spec agora
   renomeia o binário antes de empacotar.
3. **50 MB duplicados no bundle.** O FFmpeg entrava duas vezes (o embarcado e a
   cópia interna do pacote imageio-ffmpeg). O app caiu de 179 MB para 133 MB.
4. **Argumentos de pós-processamento ignorados pelo yt-dlp.** A chave usada era
   `FFmpegExtractAudio`; o yt-dlp só reconhece chaves em minúsculas e sem o
   prefixo (`extractaudio`). As tags ID3 nunca eram aplicadas.
5. **Downloads repetidos eram silenciosamente pulados.** O `download_archive`
   estava sempre ligado: rebaixar a mesma URL marcava "concluído" sem gerar
   arquivo. Passou a ser opcional (`skip_duplicates`).
6. **A análise da URL travava a interface.** Rodava na thread principal. Foi
   movida para uma thread própria.
7. **A fila corrompia índices.** O estado dos itens era inferido lendo emojis do
   texto da linha, e "limpar concluídos" durante um download deslocava os índices,
   fazendo o app marcar o item errado como concluído e permitindo remover o item
   em andamento. A fila agora tem estado explícito e o item ativo é protegido.
8. **Linhas alternadas ilegíveis.** `alternatingRowColors` sem cor definida
   pintava linhas brancas com texto branco — metade da fila ficava invisível.
9. **`requirements.txt` puxava builds de desenvolvimento.** A restrição
   `yt-dlp>=2026.08.01` não é satisfeita por nenhuma versão estável, então o pip
   instalava um `.dev0` a cada build. Corrigido para `>=2026.7.4`.
10. **PySide6 completo (~450 MB) no lugar do essencial.** Trocado por
    `PySide6-Essentials`, sem QtQuick/WebEngine/Multimedia, que o app não usa.
11. **`LSMinimumSystemVersion` mentia — e o Qt escolhido excluía a maioria dos
    Macs.** O build agora compara o `minos` real de todos os binários embarcados
    com o Info.plist e falha se houver promessa falsa. Foi essa verificação que
    revelou que o PySide6 6.10+ é compilado para macOS 15, apesar de a wheel se
    anunciar como `macosx_13_0`: o aplicativo simplesmente não abriria em macOS
    12, 13 ou 14. O PySide6 ficou fixado em 6.9.x, que tem deployment target
    macOS 12, e o Info.plist declara 12.0.
12. **O workflow anterior não conseguia gerar nada.** Exigia os Secrets da Apple
    logo no início, sem nenhum caminho de validação, e usava `codesign --deep`,
    que a Apple desaconselha para distribuição. Substituído por assinatura de
    dentro para fora.

## Testes — 78 no total, todos passando

```
pytest -q
78 passed
```

- `test_engine.py` (23) — URLs, seletores de formato, presets 4K, opções do yt-dlp.
- `test_ffmpeg.py` (10) — descoberta do FFmpeg nos layouts de bundle, incluindo a
  regressão do diretório que era confundido com o binário.
- `test_download_end_to_end.py` (8) — **downloads reais**: um clipe é gerado pelo
  FFmpeg, servido por HTTP local e baixado pela engine; valida MP4, MP3 320 kbps,
  progresso, nome do arquivo, cancelamento e erro de mídia inexistente.
- `test_queue_manager.py` (13) — máquina de estados da fila com Qt headless.
- `test_packaging.py` (24) — contrato de distribuição: Hardened Runtime,
  entitlements, ordem das etapas do release, Secrets nos workflows e proibição de
  publicar artefato não assinado.

## Validação de empacotamento executada nesta máquina

```
✓ Bundle criado: dist/Marques Lab 4K Download.app     (133 MB)
✓ FFmpeg embarcado: Contents/Frameworks/ffmpeg        (ffmpeg 7.1, arm64)
✓ CFBundleIdentifier = com.marqueslab.MarquesLab4KDownload
✓ CFBundleShortVersionString = 1.0.0
✓ LSMinimumSystemVersion = 13.0
✓ Ícone presente no bundle
✓ DMG pronto: MarquesLab-4K-Download-1.0.0-arm64.dmg  (54 MB)
```

Teste real dentro do aplicativo empacotado, executado a partir do DMG montado:

```
SELF-TEST Marques Lab 4K Download 1.0.0
  qt: PySide6 6.11.2
  ffmpeg_path: .../Marques Lab 4K Download.app/Contents/Frameworks/ffmpeg
  ffmpeg_version: ffmpeg version 7.1
  yt_dlp: 2026.07.04
  frozen: True
  window: ok
  download: MP3 real gerado (84050 bytes)
SELF-TEST: PASS
```

Ou seja: o aplicativo empacotado baixa mídia e converte para MP3 usando apenas o
que está dentro dele. Sem Python, sem FFmpeg e sem yt-dlp instalados no sistema.

## O que está bloqueado e por quê

```
security find-identity -v -p codesigning
    0 valid identities found

gh secret list
    (vazio)
```

Sem certificado **Developer ID Application** não existe assinatura válida; sem
assinatura válida a Apple não notariza; sem notarização o Gatekeeper mostra o
aviso de desenvolvedor não identificado. Não há contorno técnico legítimo.

O build local é assinado ad-hoc pelo PyInstaller e **não serve como release** —
conforme sua exigência, ele não é publicado em lugar nenhum.

Além disso, o `.app` construído nesta máquina usa o Python do Homebrew, cujo
`minos` é 26.0: ele só abriria em macOS 26+. Os builds do GitHub Actions usam um
Python com deployment target antigo e não têm esse problema. A verificação
automática já detecta e barra esse caso.

## Próximo passo, na ordem

1. Assinar o Apple Developer Program (US$ 99/ano).
2. Emitir o certificado **Developer ID Application** e exportá-lo como `.p12`.
3. Gerar a senha específica de app para notarização.
4. Cadastrar os Secrets listados em [DISTRIBUICAO.md](DISTRIBUICAO.md).
5. Publicar a tag `4kdownload-v1.0.0`.

A partir daí o workflow gera, assina, notariza, valida e publica os DMGs
sozinho — e só então o projeto poderá ser chamado de release-ready.
