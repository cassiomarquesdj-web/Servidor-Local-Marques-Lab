# Infinite Lab — Especificação Mestre

> Marques Lab Infinite Studio
> Versão: 1.0
> Status: especificação consolidada
> Princípio central: **OFFLINE-FIRST**

## 1. Visão do produto

O Infinite Lab é o estúdio desktop da Marques Lab para criação visual profissional assistida por IA. O produto reúne engenharia de prompts, projetos, presets, biblioteca de assets, geração de imagens, workflows, engines locais e organização completa do processo criativo em uma única aplicação.

O objetivo é ter uma ferramenta com aparência e comportamento de software criativo profissional — não um painel genérico de IA.

### Objetivos principais

- Criar prompts profissionais rapidamente.
- Organizar prompts, presets, estilos, modelos, workflows e resultados.
- Gerar imagens usando engines locais.
- Integrar ComfyUI local e outros engines por adapters.
- Trabalhar sem internet.
- Manter histórico completo e reproduzível das gerações.
- Permitir transportar um projeto entre computadores.
- Evitar dependência obrigatória de contas, APIs cloud ou serviços externos.

---

## 2. Regra absoluta: Offline-First

**A internet nunca pode ser requisito para o funcionamento básico do Infinite Lab.**

### Obrigatório offline

- Inicialização da aplicação.
- UI completa.
- SQLite.
- Projetos.
- Prompt Engine.
- Templates.
- Estilos.
- Favoritos.
- Histórico.
- Biblioteca local.
- Importação/exportação.
- Configurações.
- Cache.
- Thumbnails.
- Workflows locais.
- Engines locais.
- Fila de geração local.
- Recuperação de jobs após reinício.
- Logs locais.
- Pesquisa local.

### Online é opcional

- Download de modelos.
- Atualizações.
- Catálogos externos.
- Integrações cloud.
- Sincronização externa.
- Serviços de geração remota.
- Consulta a recursos externos.

Uma função online deve falhar de forma elegante quando não houver rede e nunca quebrar o núcleo local.

---

## 3. Estado já definido — Sprint 02

O Prompt Engine foi definido como núcleo inicial do produto.

### Recursos

- Autocomplete inline.
- Templates.
- Biblioteca de estilos.
- Iluminação.
- Câmeras.
- Lentes.
- Composição.
- Cores.
- Tags.
- Expansão automática de prompts.
- Histórico.
- Favoritos.
- Prompts por projeto.
- Importação/exportação JSON.
- Persistência SQLite.
- Internacionalização pt-BR / en-US.

### Validação pendente registrada

- Validação manual dos diálogos nativos de importação/exportação.

---

## 4. Sprint 03 — ComfyUI / FLUX local

Próximo grande marco do projeto.

### Objetivos

- Detectar uma instância local do ComfyUI.
- Permitir configuração manual do endereço local.
- Verificar saúde da engine.
- Listar workflows disponíveis.
- Selecionar workflow por projeto.
- Enviar prompt e parâmetros.
- Enfileirar gerações.
- Mostrar progresso.
- Permitir cancelamento.
- Capturar imagens resultantes.
- Registrar metadados.
- Associar resultados automaticamente ao projeto.
- Reexecutar uma geração.
- Permitir modo mock para testes sem ComfyUI instalado.

### Transporte

A integração pode usar HTTP/REST e WebSocket quando suportado, mas a aplicação deve encapsular tudo em um adapter próprio.

---

## 5. Abstração de engines

Nunca acoplar a UI diretamente ao ComfyUI.

Interface conceitual:

```text
EngineAdapter
├── healthCheck()
├── listModels()
├── listWorkflows()
├── submit()
├── progress()
├── cancel()
├── fetchResult()
└── capabilities()
```

### Engines previstos

- LocalComfyUI.
- FLUX local.
- Outros engines locais no futuro.
- MockEngine para testes e desenvolvimento.

O sistema deve permitir adicionar engines sem reescrever a UI ou o domínio.

---

## 6. Generation Job Manager

Toda geração deve virar um job persistente.

### Estados

```text
queued
running
completed
failed
cancelled
interrupted
recoverable
```

### Requisitos

- Fila persistente.
- Prioridade opcional.
- Cancelamento.
- Retry.
- Timeout configurável.
- Recuperação após fechamento inesperado.
- Reexecução.
- Logs por job.
- Associação ao projeto.
- Associação ao prompt.
- Associação ao workflow.
- Associação ao modelo.

---

## 7. Banco local

### Banco

SQLite é a fonte de verdade local.

### Entidades-base

- Project
- Prompt
- PromptTemplate
- Preset
- Style
- GenerationJob
- GenerationResult
- Model
- Workflow
- Asset
- Collection
- Favorite
- HistoryEntry
- AppSetting
- EngineProfile

### Requisitos de persistência

- Migrações versionadas.
- Integridade referencial.
- Backups manuais.
- Exportação/importação.
- Recuperação de banco.
- Operação sem servidor externo.

---

## 8. Estrutura de projeto

Cada projeto deve ser exportável como unidade independente.

```text
InfiniteProject/
├── project.json
├── prompts/
├── outputs/
├── assets/
├── workflows/
├── presets/
├── metadata/
└── cache/
```

### Requisito

Um projeto exportado deve poder ser copiado para outro computador e reaberto, respeitando somente as dependências locais realmente necessárias.

O sistema deve informar claramente quando algum asset, modelo ou engine local não estiver disponível.

---

## 9. Asset Library

### Funções

- Busca instantânea.
- Filtros.
- Favoritos.
- Coleções.
- Histórico.
- Preview local.
- Thumbnails persistentes.
- Metadados.
- Caminho físico.
- Hash/checksum opcional.
- Detecção de arquivo ausente.
- Relink.
- Importação.
- Exportação.

Nenhum recurso de preview local deve depender de internet.

---

## 10. Metadata e reprodutibilidade

Cada geração deve armazenar, quando disponível:

- Prompt original.
- Prompt final.
- Negative prompt.
- Seed.
- Modelo.
- Checkpoint/model version.
- Workflow.
- Parâmetros.
- Sampler.
- Scheduler.
- Steps.
- CFG.
- Resolução.
- Engine.
- Data/hora local.
- Projeto.
- Job ID.
- Caminho do resultado.

O objetivo é conseguir reproduzir uma geração posteriormente usando exatamente os mesmos dados locais.

---

## 11. Prompt Engine — evolução

Além do Sprint 02, o Prompt Engine poderá evoluir para:

- Variáveis de prompt.
- Snippets reutilizáveis.
- Presets por estilo.
- Presets por câmera.
- Presets por iluminação.
- Presets por composição.
- Presets por resolução.
- Prompt versioning.
- Comparação entre versões.
- Duplicação rápida.
- Geração em lote.
- Histórico por projeto.
- Favoritos inteligentes.
- Tags customizadas.
- Busca semântica local quando houver modelo local apropriado.

---

## 12. Workflow Manager

O Infinite Lab não deve tratar workflow como arquivo solto.

Cada workflow deverá possuir:

- Nome.
- Descrição.
- Engine compatível.
- Versão.
- Tags.
- Preview.
- Parâmetros mapeáveis.
- Entrada/saída esperada.
- Localização.
- Dependências.
- Projeto associado quando aplicável.

### Workflow parameter mapping

A UI deve mapear campos úteis do workflow para controles amigáveis, sem exigir edição manual do JSON em operações comuns.

---

## 13. Model Manager local

### Objetivos

- Detectar modelos locais.
- Indexar modelos.
- Mostrar tamanho.
- Mostrar caminho.
- Mostrar formato/tipo.
- Associar engine compatível.
- Favoritar.
- Classificar.
- Detectar modelo ausente.
- Reindexar.
- Atualizar catálogo local.

Downloads online podem existir, mas não são requisito de operação.

---

## 14. Batch Generation

Permitir executar múltiplas variações com combinação de:

- prompts
- seeds
- parâmetros
- modelos
- workflows
- resoluções

A fila deve permanecer persistente para não perder o trabalho após reinício.

---

## 15. Variações e ferramentas futuras

Roadmap funcional:

- txt2img local.
- img2img local.
- Variações.
- Inpainting.
- Outpainting.
- Upscale.
- Batch.
- Comparador A/B.
- Reutilização de parâmetros.
- Reexecução de geração.
- Presets avançados.

Cada função deve possuir versão local sempre que houver engine local compatível.

---

## 16. Cache

O cache deve ser persistente e controlável.

### Itens possíveis

- Thumbnails.
- Metadados derivados.
- Prompts expandidos.
- Resultados temporários.
- Estado de jobs.
- Dados de engines.
- Índices de biblioteca.

O usuário deve poder limpar cache sem apagar projetos ou resultados originais.

---

## 17. Privacidade e segurança

### Regras

- Sem telemetria obrigatória.
- Sem upload automático.
- Sem sincronização automática escondida.
- Logs locais configuráveis.
- Segredos nunca no Git.
- Chaves somente em armazenamento local apropriado.
- `.env.example` apenas com placeholders.
- Nenhuma credencial real em documentação, testes ou commits.

---

## 18. UX e identidade

O Infinite Lab deve parecer um software criativo profissional.

### Direção

- Desktop-first.
- Premium.
- Clean.
- Profissional.
- Responsivo.
- Alta densidade de informação quando necessário.
- Atalhos de teclado.
- Drag and drop.
- Feedback de progresso.
- Estados vazios úteis.
- Navegação rápida.

### Evitar

- aparência de dashboard SaaS genérico
- excesso de cards
- excesso de gradientes
- UI com aparência automática de IA
- dependência visual de elementos decorativos sem função

---

## 19. Internacionalização

Idiomas planejados:

- pt-BR — principal.
- en-US — secundário.

Nenhum texto essencial deve ficar hardcoded na UI quando houver suporte a i18n.

---

## 20. Arquitetura em camadas

```text
Presentation
    ↓
Application / Use Cases
    ↓
Domain
    ↓
Infrastructure
    ├── Persistence
    ├── Local Engines
    ├── File System
    ├── Cache
    └── Import / Export
```

A UI não deve conhecer detalhes de SQLite, ComfyUI ou filesystem diretamente.

---

## 21. Testes

### Obrigatórios

- Unit tests.
- Repository tests.
- SQLite tests.
- Import/export tests.
- Engine adapter tests.
- Queue tests.
- Recovery tests.
- Offline tests.
- Mock engine tests.
- Regression tests.

### Teste crítico

Executar a suíte principal com a rede indisponível.

O aplicativo deve continuar inicializando e executando todos os recursos locais.

---

## 22. CI/CD

GitHub deve ser a fonte de versionamento do código e documentação.

CI deve validar:

- build
- testes
- lint
- formatação
- migrações
- documentação crítica
- integridade dos arquivos de configuração

A CI não pode exigir acesso a API externa para validar o núcleo offline.

---

## 23. Roadmap consolidado

### Sprint 01
Bootstrap e arquitetura.

### Sprint 02
Prompt Engine.

### Sprint 03
ComfyUI / FLUX local.

### Sprint 04
Generation Queue + Job Manager.

### Sprint 05
Gallery + Asset Library.

### Sprint 06
Projects + presets avançados.

### Sprint 07
Workflow Manager.

### Sprint 08
Local Model Manager.

### Sprint 09
Batch Generation.

### Sprint 10
Upscale + variation + img2img local.

### Sprint 11
Metadata + export + reprodução de geração.

### Sprint 12
Performance + cache + recuperação.

### Sprint 13
Empacotamento desktop + documentação + hardening.

---

## 24. Critério de aceite global

Uma versão do Infinite Lab somente é considerada pronta quando:

1. funciona sem internet para os recursos locais;
2. seus dados podem ser recuperados após reinício;
3. um projeto pode ser exportado e importado;
4. uma geração local possui histórico e metadados;
5. a engine pode ser substituída por adapter;
6. falhas de rede não derrubam a aplicação;
7. falhas de engine são informadas sem corromper o projeto;
8. não existem credenciais no repositório;
9. o comportamento crítico possui testes automatizados;
10. a documentação permite que outro agente/desenvolvedor continue o projeto sem depender da conversa original.

---

## 25. Regra de evolução

Toda nova feature deve responder antes da implementação:

> **Como isso funciona com a internet desligada?**

Se não houver resposta aceitável, a feature deve ser tratada como online opcional e nunca como dependência do núcleo.

---

## 26. Fonte de verdade

Este documento é a especificação funcional e arquitetural consolidada do Infinite Lab e deve evoluir junto com o código.

Documentos derivados recomendados:

- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/OFFLINE_FIRST.md`
- `docs/ROADMAP.md`
- `docs/DATA_MODEL.md`
- `docs/ENGINE_ADAPTERS.md`
- `docs/PROJECT_FORMAT.md`
- `CHANGELOG.md`

**Nunca remover decisões arquiteturais importantes da documentação sem registrar a mudança.**
