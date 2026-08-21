# Project Scope

## Produto

**Marques Lab Camera Monitor** — monitor e controle remoto de câmeras via Wi‑Fi local para tablet Android.

## Equipamentos-alvo

- GoPro HERO 10
- GoPro MAX
- iPhone 17 Pro Max
- iPhone 16 Pro Max

## O que o app faz

- visualiza preview ao vivo;
- apresenta quatro câmeras simultaneamente;
- abre uma câmera em tela cheia;
- mostra estado real da câmera;
- mostra contador de gravação;
- envia REC/STOP quando suportado;
- confirma o resultado dos comandos;
- reconecta automaticamente;
- mostra claramente câmera offline;
- funciona em rede local sem depender de cloud.

## O que o app NÃO faz

- não grava o preview no tablet;
- não edita vídeo;
- não substitui o armazenamento interno das câmeras;
- não deve fingir suporte a comandos que o hardware não confirma;
- não depende de internet para a operação normal.

## Experiência-alvo

O operador deve conseguir colocar o tablet próximo ao setup e controlar a sessão com o mínimo de atenção possível. O preview é a prioridade visual; REC/STOP e estado são as prioridades operacionais.

## Acceptance Criteria — UX

- Quad View abre rapidamente e apresenta quatro slots consistentes;
- cada slot possui estado textual e visual;
- REC é inequívoco;
- STANDBY é inequívoco;
- OFFLINE é inequívoco;
- Single View é acessível com um toque;
- troca entre câmeras é imediata;
- controles principais possuem área de toque confortável;
- UI continua legível em ambiente escuro de evento;
- não há excesso de menus ou informação técnica na tela principal.

## Acceptance Criteria — Controle

- o app não altera o estado para REC antes do ACK;
- o app não altera o estado para STANDBY antes da confirmação;
- timeout de comando gera feedback explícito;
- falha de conexão não fica silenciosa;
- reconexão restaura o estado real quando disponível.

## Acceptance Criteria — Performance

- quatro previews simultâneos devem ser tratados como caso de primeira classe;
- buffers precisam ser limitados;
- não acumular frames indefinidamente;
- perda de um stream não pode congelar os demais;
- ao trocar para Single View, o decoder principal pode receber prioridade maior.

## Acceptance Criteria — Hardware

Antes de qualquer declaração de suporte, cada câmera deve passar pela matriz de validação em `docs/CAMERA-PROTOCOL-MATRIX.md`.
