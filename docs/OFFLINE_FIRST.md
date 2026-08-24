# Infinite Lab — Offline-First Contract

## Regra

O Infinite Lab deve continuar útil quando o computador estiver completamente sem internet.

## Deve funcionar offline

- abrir o aplicativo
- navegar pela UI
- criar/editar projetos
- criar/editar prompts
- templates e presets
- histórico e favoritos
- busca local
- biblioteca local
- importação/exportação
- SQLite e migrações
- workflows locais
- modelos locais já instalados
- ComfyUI em localhost
- geração local
- fila de jobs
- cancelamento/retry
- recuperação após reinício
- preview de arquivos locais
- logs locais
- backup e restauração local

## Pode depender da internet, mas não pode bloquear

- downloads
- atualizações
- catálogos externos
- documentação online
- sincronização externa
- serviços de geração remota

## Falhas de rede

A ausência de internet deve ser tratada como estado normal, não como exceção fatal.

Exemplo de UX:

`Offline — recursos locais disponíveis.`

Não usar telas de erro para avisar que um serviço opcional está offline.

## Teste de aceite

A suíte de testes deve possuir execução explicitamente sem acesso externo. O aplicativo deve iniciar, abrir um projeto, editar um prompt, consultar SQLite e usar uma engine mock local sem qualquer chamada à internet.

## Regra de desenvolvimento

Antes de adicionar uma dependência externa, perguntar:

1. Ela é necessária no runtime offline?
2. Existe alternativa local?
3. O aplicativo continua iniciando sem ela?
4. O build consegue usar cache/dependências previamente instaladas?
5. A funcionalidade online está claramente isolada?

## Proibição

Nunca tornar login, API key remota, CDN, serviço cloud ou sincronização online requisito para abrir ou editar projetos existentes.
