# Diagnóstico — Marques Lab 4K Download

## Estado
**MVP implementado no branch `agent/marqueslab-4k-download`.**

## Implementado
- [x] Interface desktop Marques Lab
- [x] Campo de URL
- [x] Análise de mídia
- [x] Force Download
- [x] MP4
- [x] MP3 320 kbps
- [x] Seleção de melhor qualidade
- [x] Preset 2160p/4K
- [x] Presets 1440p e 1080p
- [x] Download continuável quando suportado pela fonte
- [x] Progresso
- [x] Pasta de saída
- [x] Fila visual
- [x] Cancelamento/erro controlado pela engine
- [x] macOS launcher
- [x] Windows launcher
- [x] Testes unitários do núcleo

## Diagnóstico técnico
**Arquitetura:** PySide6 UI + engine yt-dlp + FFmpeg para pós-processamento/conversão.

**4K:** o aplicativo solicita vídeo até 2160p; se a fonte não fornecer 2160p, o mecanismo usa a melhor opção disponível dentro do preset escolhido.

**Force Download:** não depende de o site ter um botão de download. O aplicativo analisa a URL e inicia o fluxo pelo engine quando a fonte é acessível e permite a extração/download.

**Autenticação/DRM:** o aplicativo não carrega cookies nem credenciais e não implementa bypass de login, DRM ou acesso restrito.

## Validação
Os testes estáticos cobrem URL HTTP/HTTPS, rejeição de protocolos inválidos, sanitização de nomes, seleção 4K e seleção MP3.

## Próxima etapa para release real
Instalar Python, PySide6, yt-dlp e FFmpeg em uma máquina macOS/Windows e executar os testes e um download de uma URL autorizada. O empacotamento em `.app`/`.exe` pode ser feito depois que essa validação de ambiente estiver confirmada.
