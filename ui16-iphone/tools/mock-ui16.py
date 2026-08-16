#!/usr/bin/env python3
"""
Mock Soundcraft Ui16 — a dependency-free WebSocket server that emulates the mixer.

Purpose: exercise the whole app stack (connect, state sync, VU metering, keepalive,
reconnect, command writes) without physical hardware. It speaks the same wire protocol
the real mixer does, as documented in docs/protocol.md:

  * bare WebSocket on port 80 (use --port for an unprivileged port in development)
  * application payloads framed as ``3:::<payload>``
  * state as ``SETD^path^value`` (numeric) and ``SETS^path^value`` (string)
  * VU meters as ``VU2^<base64>`` at ~20 Hz
  * client sends ``ALIVE`` about once per second

It prints every command the app sends, so you can verify the app writes the exact
addresses the real mixer expects.

Usage:
    python3 tools/mock-ui16.py --port 8080
Then point the app at  <your-mac-ip>:8080  (or 127.0.0.1:8080 in the simulator).
"""

import argparse
import base64
import hashlib
import math
import os
import random
import socket
import struct
import threading
import time

WS_MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

# Ui16 inventory (see docs/protocol.md)
INPUTS, LINES, PLAYERS, FX, SUBS, AUXES = 12, 2, 2, 4, 4, 6

DEFAULT_NAMES = [
    "Kick", "Snare", "Hat", "Tom 1", "Tom 2", "OH L",
    "OH R", "Bass", "Guitar", "Keys", "Vox 1", "Vox 2",
]


# ---------------------------------------------------------------- WebSocket

def handshake(conn):
    data = b""
    while b"\r\n\r\n" not in data:
        chunk = conn.recv(4096)
        if not chunk:
            return False
        data += chunk
    key = None
    for line in data.decode("latin-1").split("\r\n"):
        if line.lower().startswith("sec-websocket-key:"):
            key = line.split(":", 1)[1].strip()
    if not key:
        return False
    accept = base64.b64encode(
        hashlib.sha1((key + WS_MAGIC).encode()).digest()
    ).decode()
    conn.send(
        (
            "HTTP/1.1 101 Switching Protocols\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Accept: {accept}\r\n\r\n"
        ).encode()
    )
    return True


def send_text(conn, text):
    payload = text.encode("utf-8")
    header = bytearray([0x81])
    n = len(payload)
    if n < 126:
        header.append(n)
    elif n < (1 << 16):
        header.append(126)
        header += struct.pack(">H", n)
    else:
        header.append(127)
        header += struct.pack(">Q", n)
    conn.sendall(bytes(header) + payload)


def recv_frames(conn):
    """Yield decoded text payloads from the socket."""
    buf = b""
    while True:
        try:
            chunk = conn.recv(4096)
        except OSError:
            return
        if not chunk:
            return
        buf += chunk
        while True:
            if len(buf) < 2:
                break
            b1, b2 = buf[0], buf[1]
            opcode = b1 & 0x0F
            masked = b2 & 0x80
            ln = b2 & 0x7F
            idx = 2
            if ln == 126:
                if len(buf) < 4:
                    break
                ln = struct.unpack(">H", buf[2:4])[0]
                idx = 4
            elif ln == 127:
                if len(buf) < 10:
                    break
                ln = struct.unpack(">Q", buf[2:10])[0]
                idx = 10
            mask = b""
            if masked:
                if len(buf) < idx + 4:
                    break
                mask = buf[idx:idx + 4]
                idx += 4
            if len(buf) < idx + ln:
                break
            data = bytearray(buf[idx:idx + ln])
            buf = buf[idx + ln:]
            if masked:
                for i in range(len(data)):
                    data[i] ^= mask[i % 4]
            if opcode == 0x8:      # close
                return
            if opcode == 0x1:      # text
                yield data.decode("utf-8", "replace")


# ---------------------------------------------------------------- Mixer model

def initial_state():
    """The state dump the mixer sends right after a client connects."""
    msgs = []
    for i in range(INPUTS):
        msgs.append(f"SETS^i.{i}.name^{DEFAULT_NAMES[i]}")
        msgs.append(f"SETD^i.{i}.mix^{round(random.uniform(0.55, 0.8), 3)}")
        msgs.append(f"SETD^i.{i}.mute^0")
        msgs.append(f"SETD^i.{i}.solo^0")
        msgs.append(f"SETD^i.{i}.pan^0.5")
        msgs.append(f"SETD^i.{i}.gain^{round(random.uniform(0.3, 0.6), 3)}")
        msgs.append(f"SETD^i.{i}.phantom^{1 if i < 4 else 0}")
        for a in range(AUXES):
            msgs.append(f"SETD^i.{i}.aux.{a}.value^{round(random.uniform(0, 0.5), 3)}")
            msgs.append(f"SETD^i.{i}.aux.{a}.post^0")
        for f in range(FX):
            msgs.append(f"SETD^i.{i}.fx.{f}.value^{round(random.uniform(0, 0.4), 3)}")
        # processing parameters that have no dedicated control in the app yet —
        # these must survive into the diagnostics layer
        msgs.append(f"SETD^i.{i}.eq.on^1")
        msgs.append(f"SETD^i.{i}.eq.high.gain^0.5")
        msgs.append(f"SETD^i.{i}.eq.mid.gain^0.5")
        msgs.append(f"SETD^i.{i}.eq.low.gain^0.5")
        msgs.append(f"SETD^i.{i}.gate.on^0")
        msgs.append(f"SETD^i.{i}.gate.thresh^0.3")
        msgs.append(f"SETD^i.{i}.dyn.on^1")
        msgs.append(f"SETD^i.{i}.dyn.thresh^0.7")
        msgs.append(f"SETD^i.{i}.hpf.on^1")
        msgs.append(f"SETD^i.{i}.hpf.freq^0.2")

    for l in range(LINES):
        msgs.append(f"SETS^l.{l}.name^Line {l + 1}")
        msgs.append(f"SETD^l.{l}.mix^0.6")
        msgs.append(f"SETD^l.{l}.mute^0")
    for p in range(PLAYERS):
        msgs.append(f"SETS^p.{p}.name^Player {p + 1}")
        msgs.append(f"SETD^p.{p}.mix^0.5")
        msgs.append(f"SETD^p.{p}.mute^0")
    for f in range(FX):
        msgs.append(f"SETD^f.{f}.mix^0.5")
        msgs.append(f"SETD^f.{f}.mute^0")
        msgs.append(f"SETD^f.{f}.fxtype^{f}")
        msgs.append(f"SETD^f.{f}.bpm^120")
    for s in range(SUBS):
        msgs.append(f"SETD^s.{s}.mix^0.5")
        msgs.append(f"SETD^s.{s}.mute^0")
    for a in range(AUXES):
        msgs.append(f"SETS^a.{a}.name^Monitor {a + 1}")
        msgs.append(f"SETD^a.{a}.mix^0.55")
        msgs.append(f"SETD^a.{a}.mute^0")

    # monitoring buses live under settings.*
    msgs.append("SETD^settings.solovol^0.6")
    msgs.append("SETD^settings.hpvol.0^0.45")

    msgs.append("SETD^m.mix^0.75")
    msgs.append("SETD^m.mute^0")
    msgs.append("SETD^m.pan^0.5")
    msgs.append("SETD^m.dim^0")
    return msgs


def vu_frame(t):
    """Build a VU2 payload with plausible moving levels."""
    counts = [INPUTS, PLAYERS, SUBS, FX, AUXES, 2, LINES]
    blocks = [6, 6, 7, 7, 5, 5, 6]
    data = bytearray(8)
    for i, c in enumerate(counts):
        data[i] = c

    def level(seed):
        # slow sine sweep + noise, scaled into the mixer's 0..240 byte range
        v = 0.5 + 0.5 * math.sin(t * 2.0 + seed)
        v = max(0.0, min(1.0, v * random.uniform(0.7, 1.0)))
        return int(v * 240)

    seed = 0
    for idx, (c, block) in enumerate(zip(counts, blocks)):
        for ch in range(c):
            seed += 1
            b = bytearray(block)
            if idx in (0, 1, 6):          # input, player, line: pre/post/postFader
                b[0] = level(seed)
                b[1] = level(seed + 0.2)
                b[2] = level(seed + 0.4)
            elif idx in (2, 3):           # sub, fx: stereo
                b[0] = level(seed)
                b[1] = level(seed + 0.1)
                b[2] = level(seed + 0.3)
                b[3] = level(seed + 0.4)
            else:                          # aux, master: post/postFader
                b[0] = level(seed)
                b[1] = level(seed + 0.2)
            data += b
    return "VU2^" + base64.b64encode(bytes(data)).decode()


# ---------------------------------------------------------------- Shows / scenes

# Shows with their snapshots and cues. "Vazio" deliberately has no cues, to exercise
# the empty-list form (`CUELIST^Vazio^`) that the real mixer sends.
SHOWS = {
    "Default": {"snapshots": ["Inicial"], "cues": ["Cue 1", "Cue 2"]},
    "Igreja": {"snapshots": ["Abertura", "Louvor", "Pregacao"], "cues": ["Entrada"]},
    "Vazio": {"snapshots": [], "cues": []},
}


def resource_reply(payload):
    """Return the reply for a resource-list request, or None if not one."""
    parts = payload.split("^")
    cmd = parts[0]

    if cmd == "SHOWLIST" and len(parts) == 1:
        return "SHOWLIST^" + "^".join(SHOWS)

    if cmd in ("SNAPSHOTLIST", "CUELIST") and len(parts) == 2:
        show = parts[1]
        key = "snapshots" if cmd == "SNAPSHOTLIST" else "cues"
        entries = SHOWS.get(show, {}).get(key, [])
        # an empty list is sent with a trailing separator and no entries
        return f"{cmd}^{show}^" + "^".join(entries)

    if cmd == "LOADSHOW" and len(parts) == 2:
        return f"SETS^var.currentShow^{parts[1]}"
    if cmd == "LOADSNAPSHOT" and len(parts) == 3:
        return f"SETS^var.currentSnapshot^{parts[2]}"
    if cmd == "LOADCUE" and len(parts) == 3:
        return f"SETS^var.currentCue^{parts[2]}"

    return None


# ---------------------------------------------------------------- Server

def serve_client(conn, addr, verbose):
    print(f"[mock-ui16] client connected: {addr[0]}:{addr[1]}")
    if not handshake(conn):
        conn.close()
        return

    stop = threading.Event()

    def pump():
        # initial state dump, batched like the real mixer
        for chunk_start in range(0, len(STATE), 40):
            batch = STATE[chunk_start:chunk_start + 40]
            try:
                send_text(conn, "3:::" + "\n".join(batch))
            except OSError:
                return
            time.sleep(0.02)
        print(f"[mock-ui16] sent {len(STATE)} state messages")
        t0 = time.time()
        while not stop.is_set():
            try:
                send_text(conn, "3:::" + vu_frame(time.time() - t0))
            except OSError:
                return
            time.sleep(0.05)   # 20 Hz

    threading.Thread(target=pump, daemon=True).start()

    alive = 0
    try:
        for frame in recv_frames(conn):
            payload = frame[4:] if frame.startswith("3:::") else frame
            if payload == "ALIVE":
                alive += 1
                if verbose and alive % 10 == 0:
                    print(f"[mock-ui16] keepalive x{alive}")
                continue
            print(f"[mock-ui16] <- {payload}")

            # Resource lists are per-client and only sent on request.
            reply = resource_reply(payload)
            if reply is not None:
                try:
                    send_text(conn, "3:::" + reply)
                except OSError:
                    break
                continue

            # echo state changes back, exactly like the mixer broadcasting to clients
            if payload.startswith(("SETD^", "SETS^")):
                try:
                    send_text(conn, "3:::" + payload)
                except OSError:
                    break
    finally:
        stop.set()
        conn.close()
        print(f"[mock-ui16] client disconnected ({alive} keepalives)")


def main():
    ap = argparse.ArgumentParser(description="Mock Soundcraft Ui16 mixer")
    ap.add_argument("--port", type=int, default=8080,
                    help="listen port (the real mixer uses 80)")
    ap.add_argument("--host", default="0.0.0.0")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    global STATE
    STATE = initial_state()

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((args.host, args.port))
    srv.listen(5)

    ip = socket.gethostbyname(socket.gethostname())
    print(f"[mock-ui16] listening on {args.host}:{args.port}")
    print(f"[mock-ui16] point the app at  {ip}:{args.port}  (simulator: 127.0.0.1:{args.port})")
    print(f"[mock-ui16] {len(STATE)} state keys, VU at 20 Hz")

    try:
        while True:
            conn, addr = srv.accept()
            threading.Thread(target=serve_client,
                             args=(conn, addr, args.verbose), daemon=True).start()
    except KeyboardInterrupt:
        print("\n[mock-ui16] shutting down")
    finally:
        srv.close()


if __name__ == "__main__":
    main()
