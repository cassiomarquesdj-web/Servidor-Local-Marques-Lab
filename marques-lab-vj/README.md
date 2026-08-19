# Marques Lab VJ

Software desktop de performance visual da Marques Lab, criado para operação de telão/LED Wall, loops, câmeras e camadas visuais em eventos.

## Versão 0.1.0

- Interface dark premium inspirada no mockup aprovado.
- Biblioteca e coleções.
- Preview/Output central.
- Layers / Colunas com 10 cenas.
- Inspector com tabs e efeitos.
- Audio Analyzer visual com BPM, espectro e métricas.
- Studio Mode / Performance Mode.
- A/B visual, Play, Auto, Auto Sync, REC e volume.
- Importação de arquivos de mídia locais para o Preview.
- Empacotamento para macOS Apple Silicon (`.dmg`).

## Rodar localmente

```bash
cd marques-lab-vj
npm install
npm start
```

## Gerar DMG no Mac

```bash
cd marques-lab-vj
npm run dist:dmg
```

O instalador é gerado em `dist/Marques-Lab-VJ-0.1.0-arm64.dmg`.

## GitHub Actions

O workflow `.github/workflows/build-macos.yml` valida o JavaScript e gera automaticamente o DMG em macOS 14 Apple Silicon, anexando o instalador como artifact.

## Arquitetura

Electron desktop com `main.js` + `preload.js` isolado e interface local em HTML/CSS/JS. Não há dependência de servidor para a interface.
