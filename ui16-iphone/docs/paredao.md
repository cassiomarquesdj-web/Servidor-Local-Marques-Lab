# Modo Paredão

Segunda experiência dentro do mesmo app. **Não substitui** o controlador técnico da Ui16 —
ele continua íntegro na aba UI16.

## Onde cada coisa é processada

Essa é a decisão mais importante do modo, e está explícita na própria interface para o
operador nunca ser enganado sobre o que está acontecendo:

| Função | Processamento | Por quê |
|---|---|---|
| Player, biblioteca, playlist | **iPhone** | Independe da mesa. |
| **EQ 5 bandas** | **iPhone** (player) | Os endereços de escrita de EQ da Ui16 **não são confirmados**. O app não finge que a mesa processa. A tela diz: *"Processado no player (dentro do iPhone), não na Ui16"*. |
| **Phase — mesa** | **Ui16**, quando o endereço existir | Ver abaixo. |
| **Phase — player** | iPhone | Desativado nesta versão, ver limitações. |
| Master, DIM, Solo, Fone | **Ui16** | Confirmado no protocolo. |
| VU do master | **Ui16** (VU2) | Confirmado. |
| VU do player | iPhone | Medido no próprio motor de áudio. |

## Arquitetura

```
ParedaoCore/            biblioteca pura, sem SwiftUI e sem UI16Controller
  Model/Track           metadados de uma faixa (nunca áudio)
  Player/PlaybackQueue  ordem, repeat e shuffle — lógica pura
  Player/PlayerController  transporte, fila, EQ e polaridade
  Library/MusicLibrary  índice, busca, pastas, favoritos, histórico
  Playlist/             playlists e reordenação
  Audio/EQSettings      5 bandas + curva (biquad RBJ) + presets
  Audio/PhaseControl    polaridade e descoberta de endereço
  Audio/AudioOutput     contrato do motor de áudio
  Persistence/          gravação atômica em disco

app/UI16Control/Paredao/
  Audio/AVAudioOutput   motor real (AVAudioEngine)
  Audio/LibraryScanner  varredura de pastas e metadados
  ParedaoStore          única camada que liga player + Ui16
  Views/                Paredão, Player, Biblioteca, EQ
```

**ParedaoCore não depende de UI16Controller.** É proposital: o player precisa continuar
tocando com a mesa fora do ar. As duas camadas só se encontram em `ParedaoStore`.
Há teste automatizado para isso (`testPlayerIsUnaffectedByMixerDisconnection`).

## Áudio

`AVAudioEngine` (não `AVPlayer`), porque o modo precisa de EQ real, estágio de polaridade e
medição de saída — nada disso o `AVPlayer` expõe.

```
player → EQ (AVAudioUnitEQ, 5 bandas) → main mixer → saída
```

Formatos decodificados nativamente: **MP3, WAV, AIFF, M4A/AAC, ALAC, CAF e FLAC**.
Verificados no simulador: WAV, M4A e AIFF.

Arquivos são lidos por segmento direto do disco, nunca carregados inteiros na memória.

### Dois bugs de áudio encontrados e corrigidos

1. **`scheduleSegment` com callback padrão.** O padrão é `.dataConsumed`, que dispara
   quando o player *leu* os dados — não quando o áudio *acabou de tocar*. A faixa
   "terminava" segundos antes e o set corria adiante. Corrigido para `.dataPlayedBack`.

2. **Relógio de transporte travado.** O tick só atualizava o tempo quando
   `AVAudioPlayerNode.isPlaying` era verdadeiro, e esse flag não é indicador confiável de
   progresso de render: o áudio tocava e trocava de faixa, mas o cronômetro ficava em 0:00.
   Agora o tick usa o próprio estado do motor e o tempo tem fallback de relógio de parede.

## Biblioteca

- Importa **pasta** ou **arquivos** pelo Files, com **security-scoped bookmark**: os
  arquivos ficam onde estão, nada é copiado para dentro do app.
- A pasta do próprio app também aparece no Files (`UIFileSharingEnabled`), então dá para
  jogar músicas lá direto pelo Files, AirDrop ou Finder.
- Subpastas são varridas recursivamente.
- Reindexar a mesma pasta **atualiza** metadados sem duplicar e sem perder id, favoritos
  ou referências de playlist.
- Busca instantânea com acento dobrado ("sertao" acha "Sertão") e termos em AND.
  O `searchKey` é pré-computado na indexação; há teste com 5000 faixas.
- Artwork é reduzida para 300 px e guardada em disco, carregada sob demanda — capas em
  tamanho cheio de milhares de faixas não caberiam na memória.

## PHASE — como o endereço é descoberto

O endereço de polaridade da Ui16 **não é público**. Em vez de chutar uma chave:

1. A mesa envia todo o seu estado ao conectar.
2. `PhaseControl.resolve(channelAddress:reportedKeys:)` procura, **entre as chaves que a
   mesa realmente reportou**, um parâmetro de polaridade daquele canal
   (`phase`, `polarity`, `invert`, `pol`, `phaseinvert`).
3. Enquanto nenhuma chave real aparecer, o estado é `.unconfirmed`, o botão fica
   desabilitado e **nada é transmitido**. A interface explica o motivo.
4. Quando aparecer, o botão passa a operar pelo endereço verdadeiro, mostra
   NORMAL/INVERTIDA, indica "aguardando confirmação" enquanto a escrita está em voo, e
   sincroniza com o eco da mesa (inclusive mudanças feitas na própria mesa).

Ou seja: **ao conectar na sua Ui16, se ela tiver polaridade, o botão se habilita sozinho.**

## Limitações honestas

- **Inversão de polaridade local do player está DESATIVADA.** Escrevi uma AudioUnit
  própria (`PolarityAudioUnit`) porque o iOS não tem efeito de polaridade pronto. Inserida
  no grafo, ela **trava a renderização** — a reprodução congelava. Preferi desligá-la a
  embarcar áudio quebrado. O código continua no repositório e a interface diz que está
  indisponível. Religar é uma linha depois de corrigir o render.
- **Waveform é uma forma estável derivada da posição**, não a análise real do arquivo.
  Decodificar milhares de faixas para desenhar waveform real seria inviável no celular.
  O campo de barras responde ao nível de saída ao vivo.
- **EQ não é enviado para a mesa** (ver tabela acima).
- **Salvar snapshot/cue** existe na biblioteca mas continua sem botão, de propósito.

## Testes

172 testes no total, todos passando (`swift test`), sem simulador nem hardware:

| Área | Cobertura |
|---|---|
| Fila | repeat off/all/one, shuffle determinístico, avanço automático vs. manual, remoção, "tocar em seguida" |
| Biblioteca | busca com acento, por artista/pasta, termos em AND, dedupe por caminho, favoritos, histórico, ordenação, 5000 faixas |
| Playlist | criar, renomear, nomes duplicados, reordenar (inclusive múltiplos), prune |
| EQ | curva biquad real, shelf x peak, bypass por banda e global, clamp, presets, round-trip Codable |
| Phase | resolução de endereço, recusa quando não confirmado, não confunde canais, confirmação em voo |
| Player | transporte, encadeamento, repeat, arquivo corrompido é pulado, EQ/polaridade reaplicados por faixa |
| Integração | player continua tocando com a mesa caindo; estado da mesa não mexe no EQ do player |
| Persistência | round-trip, arquivo corrompido não trava o app, 3000 faixas |

## O que só pode ser validado na Ui16 física

1. Se a mesa expõe parâmetro de polaridade e com que nome — isso **habilita o botão PHASE
   da mesa automaticamente**.
2. Confirmação de escrita de master/DIM/solo/fone junto com o player tocando.
3. Comportamento do áudio do iPhone entrando na mesa (ganho de entrada, headroom).
4. Latência real do conjunto player + mesa em rede Wi-Fi de evento.
