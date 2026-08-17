import ParedaoCore
import SwiftUI

/// Full player: artwork, transport, seek, waveform, volume, repeat/shuffle and the queue.
struct PlayerPage: View {
    @ObservedObject var paredao: ParedaoStore
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    private var player: PlayerController { paredao.player }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                artwork
                titleBlock
                seekBlock
                transport
                modeRow
                volumeRow
                if let error = player.lastError { errorRow(error) }
                queueBlock
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 20)
        }
    }

    private var artwork: some View {
        Artwork(url: player.current.flatMap(paredao.artworkURL), size: 260, corner: 16)
            .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
            .padding(.top, 4)
    }

    private var titleBlock: some View {
        VStack(spacing: 4) {
            Text(player.current?.displayTitle ?? "Nada tocando")
                .font(.system(size: 20, weight: .heavy))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(player.current?.displayArtist ?? "—")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textDim)
                .lineLimit(1)
            if let track = player.current, !track.album.isEmpty {
                Text(track.album).font(.system(size: 11)).foregroundStyle(Theme.textDim.opacity(0.7))
            }
        }
    }

    // MARK: Seek + waveform

    private var seekBlock: some View {
        VStack(spacing: 6) {
            WaveformSeekBar(
                progress: scrubbing ? scrubValue : player.snapshot.progress,
                level: max(player.snapshot.levelL, player.snapshot.levelR),
                onScrub: { value in
                    scrubbing = true
                    scrubValue = value
                },
                onCommit: { value in
                    player.seek(progress: value)
                    scrubbing = false
                }
            )
            .frame(height: 60)

            HStack {
                Text(Track.timeText(scrubbing
                                    ? scrubValue * player.snapshot.duration
                                    : player.snapshot.currentTime))
                Spacer()
                Text("-" + Track.timeText(player.snapshot.remaining))
            }
            .font(.system(size: 12, weight: .semibold).monospacedDigit())
            .foregroundStyle(Theme.textDim)
        }
    }

    // MARK: Transport

    private var transport: some View {
        HStack(spacing: 12) {
            circleButton("backward.fill", 22, 62) { player.previous() }
            Button {
                player.togglePlayPause()
                hapticTap()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 34, weight: .bold))
                    .frame(width: 88, height: 88)
                    .foregroundStyle(.black)
                    .background(Theme.accent)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            circleButton("forward.fill", 22, 62) { player.next() }
        }
    }

    private func circleButton(_ icon: String, _ size: CGFloat, _ frame: CGFloat,
                              action: @escaping () -> Void) -> some View {
        Button {
            action()
            hapticTap()
        } label: {
            Image(systemName: icon)
                .font(.system(size: size, weight: .bold))
                .frame(width: frame, height: frame)
                .foregroundStyle(Theme.text)
                .background(Theme.surfaceHigh)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Modes

    private var modeRow: some View {
        HStack(spacing: 10) {
            ConsoleButton(title: "SHUFFLE",
                          subtitle: player.isShuffled ? "LIGADO" : "DESLIGADO",
                          isOn: player.isShuffled, onColor: Theme.accent) {
                player.toggleShuffle()
            }
            ConsoleButton(title: "REPEAT",
                          subtitle: repeatLabel,
                          isOn: player.repeatMode != .off,
                          onColor: Theme.accent) {
                player.cycleRepeat()
            }
        }
    }

    private var repeatLabel: String {
        switch player.repeatMode {
        case .off: return "DESLIGADO"
        case .all: return "TUDO"
        case .one: return "UMA"
        }
    }

    private var volumeRow: some View {
        Panel {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "speaker.fill").font(.system(size: 11))
                    Text("VOLUME DO PLAYER").font(Theme.label)
                    Spacer()
                    Text("\(Int(player.snapshot.volume * 100))%")
                        .font(Theme.value).foregroundStyle(Theme.accent)
                }
                .foregroundStyle(Theme.textDim)
                Slider(value: Binding(get: { player.snapshot.volume },
                                      set: { player.setVolume($0) }), in: 0...1)
                    .tint(Theme.accent)
            }
        }
    }

    private func errorRow(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message).font(.system(size: 12, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("OK") { player.clearError() }
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.black)
        }
        .padding(10)
        .background(Theme.solo)
        .foregroundStyle(.black)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: Queue

    private var queueBlock: some View {
        let upcoming = player.queue.upcoming(limit: 30)
        return Group {
            if !upcoming.isEmpty {
                Panel {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("A SEGUIR · \(player.queue.count) NA FILA")
                            .font(Theme.label).foregroundStyle(Theme.textDim)
                        ForEach(Array(upcoming.enumerated()), id: \.element.id) { _, track in
                            HStack(spacing: 10) {
                                Artwork(url: paredao.artworkURL(for: track), size: 34, corner: 6)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(track.displayTitle)
                                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                    Text(track.displayArtist)
                                        .font(.system(size: 10)).foregroundStyle(Theme.textDim).lineLimit(1)
                                }
                                Spacer()
                                Text(track.durationText)
                                    .font(.system(size: 11).monospacedDigit())
                                    .foregroundStyle(Theme.textDim)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if let index = player.queue.tracks.firstIndex(of: track) {
                                    player.play(tracks: player.queue.tracks, startAt: index)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Seek bar drawn as a waveform-style bar field.
///
/// The bars are a deterministic shape derived from the track position plus the live output
/// level, giving useful motion without decoding the whole file to compute a real waveform —
/// which would be far too slow for a library of thousands of tracks on a phone.
struct WaveformSeekBar: View {
    let progress: Double
    let level: Double
    let onScrub: (Double) -> Void
    let onCommit: (Double) -> Void

    private let barCount = 56

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let played = Int((Double(barCount) * progress).rounded())

            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { i in
                    let base = barHeight(i)
                    let boost = i == played ? level * 0.5 : 0
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(i <= played ? Theme.accent : Theme.surfaceHigh)
                        .frame(height: max(3, height * min(1, base + boost)))
                }
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in onScrub(min(max(g.location.x / width, 0), 1)) }
                    .onEnded { g in onCommit(min(max(g.location.x / width, 0), 1)) }
            )
        }
    }

    /// Stable pseudo-random bar profile — same shape every render, so the waveform does
    /// not jitter while playing.
    private func barHeight(_ index: Int) -> Double {
        let x = Double(index)
        let a = sin(x * 0.7) * 0.25
        let b = sin(x * 0.31 + 1.3) * 0.2
        let c = sin(x * 1.7 + 0.4) * 0.12
        return 0.45 + a + b + c
    }
}
