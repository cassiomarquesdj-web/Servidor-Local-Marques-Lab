import ParedaoCore
import SwiftUI
import UI16Controller

/// Root navigation for the whole app.
///
/// The Ui16 technical controller is one destination among five, not something Paredão mode
/// replaces. All destinations share one `ParedaoStore`, so switching to UI16 and back never
/// interrupts playback — the audio engine lives above the navigation.
struct ParedaoShell: View {
    @ObservedObject var paredao: ParedaoStore
    @ObservedObject var mixer: UI16Store
    @Binding var host: String

    @State private var mode: Mode = .paredao

    enum Mode: String, CaseIterable, Identifiable {
        case paredao, player, library, eq, ui16
        var id: String { rawValue }

        var label: String {
            switch self {
            case .paredao: return "PAREDÃO"
            case .player: return "PLAYER"
            case .library: return "BIBLIOTECA"
            case .eq: return "EQ"
            case .ui16: return "UI16"
            }
        }
        var icon: String {
            switch self {
            case .paredao: return "speaker.wave.3.fill"
            case .player: return "play.circle.fill"
            case .library: return "music.note.list"
            case .eq: return "slider.horizontal.below.rectangle"
            case .ui16: return "slider.vertical.3"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch mode {
                case .paredao:
                    ParedaoHome(paredao: paredao, mixer: mixer, onOpenPlayer: { mode = .player })
                case .player:
                    PlayerPage(paredao: paredao)
                case .library:
                    LibraryPage(paredao: paredao)
                case .eq:
                    EQPage(paredao: paredao)
                case .ui16:
                    // The original technical controller, untouched.
                    MixerView(store: mixer, host: $host)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // A now-playing strip follows the operator everywhere except the full player,
            // so the music is always one tap away — including inside the Ui16 controller.
            if mode != .player, paredao.player.current != nil {
                NowPlayingBar(paredao: paredao) { mode = .player }
            }

            ModeBar(mode: $mode)
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}

struct ModeBar: View {
    @Binding var mode: ParedaoShell.Mode

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ParedaoShell.Mode.allCases) { m in
                Button {
                    mode = m
                    hapticTap()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: m.icon).font(.system(size: 17, weight: .semibold))
                        Text(m.label)
                            .font(.system(size: 9, weight: .bold))
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity, minHeight: Theme.tapMin)
                    .foregroundStyle(mode == m ? Theme.accent : Theme.textDim)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
        .background(Color.black)
    }
}

/// Compact transport shown outside the player page.
struct NowPlayingBar: View {
    @ObservedObject var paredao: ParedaoStore
    let onTap: () -> Void

    var body: some View {
        let player = paredao.player
        HStack(spacing: 10) {
            Artwork(url: player.current.flatMap(paredao.artworkURL), size: 38)

            VStack(alignment: .leading, spacing: 1) {
                Text(player.current?.displayTitle ?? "—")
                    .font(.system(size: 13, weight: .bold)).lineLimit(1)
                Text(player.current?.displayArtist ?? "")
                    .font(.system(size: 10)).foregroundStyle(Theme.textDim).lineLimit(1)
            }

            Spacer(minLength: 4)

            HStack(spacing: 3) {
                MeterBar(level: player.snapshot.levelL).frame(width: 4)
                MeterBar(level: player.snapshot.levelR).frame(width: 4)
            }
            .frame(height: 26)

            Button {
                player.togglePlayPause()
                hapticTap()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 46, height: 46)
                    .foregroundStyle(Theme.text)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Theme.surface)
        .overlay(alignment: .top) {
            // Thin progress line so elapsed position is readable without opening the player.
            GeometryReader { geo in
                Rectangle().fill(Theme.accent)
                    .frame(width: geo.size.width * player.snapshot.progress, height: 2)
            }
            .frame(height: 2)
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

/// Cover art with a graceful placeholder.
struct Artwork: View {
    let url: URL?
    var size: CGFloat = 60
    var corner: CGFloat = 8

    var body: some View {
        Group {
            if let url, let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Theme.surfaceHigh
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.35))
                        .foregroundStyle(Theme.textDim)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    }
}
