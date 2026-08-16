# Protocolo Soundcraft Ui16 — o que está confirmado

Este documento registra **cada comando** que o app usa, de onde veio a confirmação e o
que ainda depende de teste na mesa física.

Regra do projeto: **nenhum comando é inventado.** Se um parâmetro não tem endereço de
escrita confirmado, ele não ganha um botão que finge funcionar — ele aparece na camada de
diagnóstico com a chave real que a mesa reportou.

## Fontes

| Fonte | Peso |
|---|---|
| [fmalcher/soundcraft-ui](https://github.com/fmalcher/soundcraft-ui) — biblioteca de referência para Ui12/Ui16/Ui24R, em uso em produção (Bitfocus Companion) | Alta — é a implementação aberta mais completa |
| Comportamento observado da Ui Series (fóruns Harman, notas de engenharia reversa) | Média |
| Mesa Ui16 física | **Ainda não realizado** — ver "Pendências" |

## Transporte

| Item | Valor | Confirmação |
|---|---|---|
| Endpoint | `ws://<ip>` (porta 80) | `mixer-connection.ts` |
| Frame de saída | `3:::<payload>` | serializer `3:::${msg}` |
| Frame de entrada | prefixo `3:::` removido; várias mensagens separadas por `\n` | idem |
| Keepalive | `ALIVE` a cada 1 s | `keepaliveTime = 1000` |
| Ping `2::` | a mesa envia; a referência não responde | `mixer-connection.ts` (filtro comentado) |

## Mensagens de estado

| Forma | Tipo do valor |
|---|---|
| `SETD^<chave>^<valor>` | **numérico** (níveis 0..1, booleanos como 0/1, enums) |
| `SETS^<chave>^<valor>` | **texto** (nomes de canal, shows) |
| `VU2^<base64>` | bloco binário de VU (~20 Hz) |

O valor pode conter `^`; tudo depois do segundo separador é o valor.

> Correção aplicada: a versão anterior tratava nome de canal como `SETD`. Nomes são `SETS`.

## Inventário real da Ui16

A Ui16 **não** tem 16 canais mono. São 16 *fontes* de entrada:

| Tipo | Prefixo | Quantidade | Endereços |
|---|---|---|---|
| Entrada mono | `i` | 12 | `i.0` … `i.11` |
| Entrada de linha | `l` | 2 | `l.0`, `l.1` |
| Player | `p` | 2 | `p.0`, `p.1` |
| FX | `f` | 4 | `f.0` … `f.3` |
| Sub group | `s` | 4 | `s.0` … `s.3` |
| AUX | `a` | 6 | `a.0` … `a.5` |
| VCA | `v` | — | só Ui24R |

Confirmação: `channel-sync-mapping.ts`, mapeamento `ui16`.

> Correção aplicada: a versão anterior endereçava `i.0`…`i.15`, o que escreveria em
> canais inexistentes e nunca alcançaria line/player.

## Comandos — leitura e escrita

Todos abaixo usam `SETD` salvo indicação contrária. `<c>` = índice 0-based do canal.

| Parâmetro | Chave | Valor | Leitura | Escrita | Confirmação |
|---|---|---|---|---|---|
| Fader do canal | `<t>.<c>.mix` | 0..1 | ✅ | ✅ | `channel.ts` |
| Mute | `<t>.<c>.mute` | 0/1 | ✅ | ✅ | `channel.ts` |
| Solo | `<t>.<c>.solo` | 0/1 | ✅ | ✅ | `master-channel.ts` |
| Pan | `<t>.<c>.pan` | 0..1 | ✅ | ✅ | `master-channel.ts` |
| Ganho (preamp) | `i.<c>.gain` | 0..1 → −40..+50 dB | ✅ | ✅ | `hw-channel.ts` |
| Phantom 48V | `i.<c>.phantom` | 0/1 | ✅ | ✅ | `hw-channel.ts` |
| Nome do canal | `<t>.<c>.name` (**SETS**) | texto | ✅ | ✅ | `channel.ts` |
| Send AUX/FX | `<t>.<c>.<bus>.<b>.value` | 0..1 | ✅ | ✅ | `send-channel.ts` |
| Send pre/post | `<t>.<c>.<bus>.<b>.post` | 0/1 | ✅ | ✅ | `send-channel.ts` |
| Stereo link | `<t>.<c>.stereoIndex` | −1/0/1 | ✅ | — | `state-selectors.ts` |
| Master fader | `m.mix` | 0..1 | ✅ | ✅ | `state-selectors.ts` |
| Master mute | `m.mute` | 0/1 | ✅ | ✅ | idem |
| Master pan | `m.pan` | 0..1 | ✅ | ✅ | idem |
| Master dim | `m.dim` | 0/1 | ✅ | ✅ | idem |
| Tipo de FX | `f.<b>.fxtype` | 0=Reverb,1=Delay,2=Chorus,3=Room | ✅ | ✅ | `types.ts` |
| BPM do FX | `f.<b>.bpm` | número | ✅ | ✅ | `state-selectors.ts` |

> Correção aplicada: o master era endereçado como `m.0.mix`. O correto é `m.mix`
> (sem índice). Sends usavam `i.<c>.aux.<b>`; falta o sufixo `.value`.

## Curva do fader (dB)

O fader da Ui **não é linear em dB**. A posição 0..1 passa por esta função de
transferência (de `value-converters.ts`) antes de virar amplitude:

```
sin(28.5599 · v)            se v < 0.055, senão 1
× exp((23.9084 + (−26.2388 + (12.1952 − 0.4878·v)·v)·v)·v)
× 2.6765e−4
```

dB = `20·log10(amplitude)`, chegando a **+10 dB** no topo. A inversa (dB → posição) usa
método de Newton. Implementado em `FaderMath.swift`, com testes de ida e volta.

> Correção aplicada: a versão anterior exibia `valor × 100 − 100`, que mostra dB errado
> em toda a extensão do fader.

Outras faixas:
- **Ganho** Ui12/Ui16: mapeamento linear 0..1 → −40..+50 dB.
- **VU**: mapeamento linear 0..1 → −80..0 dB.

## VU2 — formato binário

Preâmbulo de 8 bytes; bytes 0..6 são as **quantidades** por tipo, nesta ordem fixa.
Cada canal ocupa um bloco de tamanho fixo. Fator de normalização `0.004167508166392142`.

| Ordem | Tipo | Byte de contagem | Bloco | Campos |
|---|---|---|---|---|
| 1 | input | 0 | 6 | pre, post, pós-fader |
| 2 | player | 1 | 6 | pre, post, pós-fader |
| 3 | sub | 2 | 7 | postL, postR, pós-faderL, pós-faderR |
| 4 | fx | 3 | 7 | postL, postR, pós-faderL, pós-faderR |
| 5 | aux | 4 | 5 | post, pós-fader |
| 6 | master | 5 | 5 | post, pós-fader (índice 0 = L, 1 = R) |
| 7 | line | 6 | 6 | pre, post, pós-fader |

Confirmação: `vu.utils.ts`. O decodificador anterior já estava **correto**; foi mantido
e apenas reempacotado em tipos com testes.

## Parâmetros sem escrita confirmada

**EQ, Gate, Compressor, Phase, HPF.**

A biblioteca de referência não expõe endereços de escrita para esses blocos, e não há
documentação pública confiável. Portanto o app **não inventa** chaves como
`i.0.eq.high.gain`.

O que o app faz:

1. **Preserva tudo.** Toda chave `SETD`/`SETS` recebida vai para `state.raw`, mesmo sem
   controle dedicado.
2. **Mostra o que existe.** A aba CANAL lista os parâmetros de processamento que a mesa
   realmente reportou para aquele canal, com a chave exata.
3. **Permite operar.** Cada parâmetro pode ser escrito pelo seu endereço real
   (`sendRawNumber`), sem o app supor nomes.

Assim, **assim que a Ui16 física for conectada**, os endereços reais aparecem sozinhos no
painel e já ficam operáveis — sem alterar código.

## Cenas / shows — implementado

Shows, snapshots e cues **não** fazem parte do estado `SETD`/`SETS`. São listas por
cliente, enviadas apenas quando solicitadas. Confirmação: `show-controller.ts` e
`resource-lists.ts`.

| Ação | Mensagem | Resposta |
|---|---|---|
| Listar shows | `SHOWLIST` | `SHOWLIST^<show>^<show>…` |
| Listar snapshots | `SNAPSHOTLIST^<show>` | `SNAPSHOTLIST^<show>^<snap>…` |
| Listar cues | `CUELIST^<show>` | `CUELIST^<show>^<cue>…` |
| Carregar show | `LOADSHOW^<show>` | estado é reemitido |
| Carregar snapshot | `LOADSNAPSHOT^<show>^<snap>` | idem |
| Carregar cue | `LOADCUE^<show>^<cue>` | idem |
| Salvar snapshot | `SAVESNAPSHOT^<show>^<snap>` | sobrescreve |
| Salvar cue | `SAVECUE^<show>^<cue>` | sobrescreve |

O que está carregado chega como estado normal: `var.currentShow`,
`var.currentSnapshot`, `var.currentCue`.

Detalhes que o app trata:

- As listas são **por cliente**: precisam ser pedidas a cada (re)conexão. O app faz isso
  automaticamente ao conectar.
- Lista vazia vem com separador final (`CUELIST^Default^`) e **não** deve virar uma
  entrada de nome vazio.
- Recall é destrutivo (substitui a mistura ao vivo), então o app **pede confirmação**
  antes de carregar.

Validado contra o mock, incluindo o caso de show sem snapshots/cues.
Falta confirmar na mesa física apenas o comportamento de `SAVESNAPSHOT`/`SAVECUE`
(o app ainda não expõe botão de salvar, para evitar sobrescrever um show por engano).

## Pendências que exigem a Ui16 física

Nada abaixo pôde ser verificado sem o hardware:

1. **Confirmar cada escrita** — que a mesa aceita e ecoa cada comando da tabela acima.
2. **Descobrir os endereços de EQ/Gate/Comp/HPF/Phase** — bastará abrir a aba CANAL
   conectado à mesa e ler as chaves listadas.
3. **Faixa e unidade de `gain`** — validar se −40..+50 dB confere com o display da mesa.
4. **Cenas/presets** — capturar as mensagens reais para então implementar.
5. **Comportamento de `stereoIndex`** — canais linkados devem receber o comando em par.
6. **Latência e taxa de escrita** — a janela de coalescência (40 ms) foi escolhida por
   segurança; ajustar se a mesa aceitar mais.

O que **já foi validado sem hardware**, contra um mock que fala o protocolo real
(`tools/mock-ui16.py`): conexão, keepalive, reconexão automática, dump de estado,
decodificação de VU2, nomes de canal via SETS, e os endereços exatos escritos pelo app.
