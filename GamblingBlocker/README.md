# Gambling Blocker — iPhone

Bloqueador estrito de jogos de azar e apostas.

## Objetivo
Impedir o acesso a conteúdo de gambling usando as APIs nativas do iOS e uma política de bloqueio ampla.

## Camadas

1. Family Controls / Screen Time para autorização e restrições.
2. Managed Settings para aplicar bloqueios de sites/apps compatíveis.
3. Network Extension Content Filter para filtragem de tráfego quando o dispositivo e o entitlement permitirem.
4. Catálogo de categorias e palavras-chave atualizado remotamente.
5. Modo STRICT: sem fluxo normal de desbloqueio dentro do aplicativo.

## Importante
A Apple impõe restrições de entitlement e distribuição ao Content Filter. Em particular, o uso como filtro de conteúdo via Screen Time possui requisitos específicos de dispositivo/conta, e o entitlement Family Controls para distribuição precisa de aprovação da Apple. A implementação final deve ser validada em um iPhone físico com o Apple Developer Program.

## Build

Abra `GamblingBlocker` no Xcode e configure:

- iOS deployment target conforme os targets escolhidos.
- Family Controls.
- App Groups.
- Network Extensions / Content Filter quando aprovado para o App ID.
- Signing & Capabilities com a equipe Apple Developer.

## Produto

A V1 não promete bloqueio matematicamente absoluto de toda a Internet. Ela foi desenhada para maximizar a cobertura de gambling dentro das APIs permitidas pela Apple e impedir bypass pelo fluxo normal do aplicativo.
