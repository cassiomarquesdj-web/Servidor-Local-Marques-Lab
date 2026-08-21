# Architecture — Camera Monitor Android

## Stack

- Flutter / Dart
- Riverpod para estado e composição de dependências
- GoRouter somente se a navegação crescer o suficiente para justificar rotas nomeadas
- camada de transporte isolada do domínio
- player/decoder substituível para cada tipo de stream

## Camadas

```text
ui/
  screens/
  widgets/
  theme/

application/
  providers/
  commands/
  session_controller.dart

domain/
  camera.dart
  camera_state.dart
  camera_command.dart
  camera_capabilities.dart
  camera_session.dart

infrastructure/
  protocols/
    gopro/
    iphone/
  preview/
  networking/
  diagnostics/
```

## Domain model

### Camera

```text
id
name
model
manufacturer
transport
capabilities
state
recordingDuration
lastSeen
signal/connection quality
```

### CameraState

```text
offline
connecting
standby
recording
error
unsupported
```

### CameraCommand

```text
startRecording
stopRecording
refreshState
reconnect
```

## State machine

```text
OFFLINE
  │
  └─ connect ──> CONNECTING
                   │
             success│ failure
                   ▼      ▼
                STANDBY  OFFLINE
                   │
             start │
                   ▼
                 REC
                   │
              stop │
                   ▼
                STANDBY
```

A command cannot directly mutate the state. The protocol adapter must emit an acknowledgement/event.

## Command pipeline

```text
UI button
   ↓
CameraSessionController
   ↓
CameraCommandQueue
   ↓
ProtocolAdapter
   ↓
Device
   ↓
ACK / STATE
   ↓
CameraStateMachine
   ↓
UI
```

## Preview pipeline

Preview ingestion is independent from control state. A camera may have:

- control connection available but no preview;
- preview available but remote control unavailable;
- both available;
- neither available.

The UI must display these cases independently instead of treating `online = preview + remote control`.

## Multi-camera resource policy

The default target is four previews. The app must avoid buffering unlimited frames.

Recommended policy:

- bounded decoder buffers;
- frame dropping under UI pressure;
- no recording of incoming preview frames;
- lifecycle-aware pause of non-visible single-view decoders when safe;
- Quad View uses lower preview resolution than Single View when the source supports adaptive quality.

## Local network

The intended topology is a dedicated local Wi-Fi network. Internet access is not a functional dependency for monitoring.

No cloud relay is required by the product design.

## Security

- never store camera credentials in plaintext;
- keep credentials in Android secure storage where needed;
- do not expose camera endpoints unnecessarily outside the local network;
- make diagnostics optional and non-sensitive.

## Failure handling

Every camera session needs:

- connection timeout;
- retry/backoff;
- last-known-state timestamp;
- explicit `stale` handling;
- user-visible reconnection state.

## Test strategy

Unit tests:

- state machine;
- command acknowledgement;
- timeout/retry;
- adapter mapping;
- capability discovery.

Integration tests:

- each camera adapter independently;
- preview pipeline independently;
- simultaneous four-camera session;
- Wi-Fi reconnect.

Hardware acceptance:

The hardware matrix in `CAMERA-PROTOCOL-MATRIX.md` is authoritative for what is actually supported on each device.