# Marques Lab UI16 iPhone

Aplicativo iPhone dedicado ao controle remoto da Soundcraft Ui16.

## Objetivo

Interface mobile-first para operação rápida da Ui16 em tela pequena, com controles grandes, navegação por abas e ações críticas acessíveis com poucos toques.

## Estrutura

- `ios/` projeto nativo iOS/SwiftUI
- `Sources/` protocolo, estado e telas
- `Tests/` testes unitários e de protocolo
- `docs/` decisões técnicas e protocolo

## Princípios de UX

- uma mão
- controles grandes
- feedback visual imediato
- conexão Wi-Fi local
- nenhuma dependência de internet para operar a mesa
- prevenção de toques acidentais em Mute/Cena

## Status

Base inicial criada. Próximos commits devem entregar conexão real, leitura de estado e escrita de parâmetros na Ui16, seguida de testes em dispositivo iPhone.
