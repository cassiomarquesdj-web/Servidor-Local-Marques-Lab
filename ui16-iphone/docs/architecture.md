# UI16 iPhone — Architecture

## Runtime

- SwiftUI
- URLSessionWebSocketTask for local WebSocket transport
- Observable state store
- Actor-isolated connection engine
- No cloud dependency during live operation

## Transport

Soundcraft Ui uses a WebSocket endpoint on the mixer's local IP. The protocol wraps outbound payloads with `3:::`. Keepalive is `ALIVE` approximately every second. Incoming frames can contain multiple newline-separated messages and are split before parsing.

## State protocol

Most state updates are text messages in the form:

`SETD^key^value`

The mixer sends its current state after connection initialization, and state changes are broadcast to connected clients.

## iPhone UX

Default portrait layout:

1. Connection header
2. Master strip with large Master fader and Mute
3. Favorite/quick channels
4. Horizontal channel navigator
5. Selected channel controls
6. Bottom tabs: Mixer / Channel / FX / Aux / Shows / Settings

Controls use a minimum 44pt touch target, with critical mute actions separated from navigation gestures.

## Safety

- Debounce repeated writes from drag gestures.
- Local optimistic UI only for controls with reversible state.
- Connection loss must visibly lock or mark stale controls.
- Reconnect automatically after Wi-Fi interruption.
