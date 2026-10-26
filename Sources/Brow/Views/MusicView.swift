import SwiftUI

// One card tinted by the artwork: the cover at full height on the left, the song and its controls beside it,
// and the lyrics in a column on the right when the song has any.
struct MusicView: View {
    @EnvironmentObject var media: MediaController
    @EnvironmentObject var lyrics: Lyrics

    var body: some View {
        if let now = media.now {
            let tint = media.tint ?? Theme.accent
            let showsLyrics = lyrics.state == .synced || lyrics.state == .plain || lyrics.state == .loading
            // Narrow layouts drop the lyrics column rather than squeeze or spill the player.
            ViewThatFits(in: .horizontal) {
                if showsLyrics {
                    row(now, tint: tint, lyrics: true, bigArt: true)
                    row(now, tint: tint, lyrics: true, bigArt: false)
                }
                row(now, tint: tint, lyrics: false, bigArt: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [tint.opacity(0.2), tint.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(tint.opacity(0.18)))
            .animation(.easeInOut(duration: 0.35), value: media.tint)
            .animation(.easeInOut(duration: 0.25), value: showsLyrics)
        } else {
            Placeholder(icon: "music.note", title: "Nothing playing",
                        caption: "Play something in any app: Spotify, Music, or YouTube in your browser")
        }
    }

    // Wide enough: cover, player and lyrics side by side. Less room: the cover moves next to the title.
    private func row(_ now: NowPlaying, tint: Color, lyrics: Bool, bigArt: Bool) -> some View {
        HStack(spacing: 18) {
            if bigArt { Artwork(tint: tint) }
            // Ideal widths are what the fit check measures, so they're kept at what each column can live with.
            PlayerColumn(now: now, tint: tint, inlineArt: !bigArt).frame(minWidth: 230, idealWidth: 230, maxWidth: .infinity)
            if lyrics {
                Rectangle().fill(Theme.stroke).frame(width: 1).padding(.vertical, 4)
                LyricsColumn(now: now, tint: tint).frame(minWidth: 180, idealWidth: 180, maxWidth: 280)
            }
        }
    }
}

// Always square: a 16:9 video thumbnail is cropped to its centre rather than stretching the box.
private struct Artwork: View {
    @EnvironmentObject var media: MediaController
    let tint: Color
    var side: CGFloat?

    var body: some View {
        let square = Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let art = media.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Theme.ink.opacity(0.08)
                        Image(systemName: "music.note").font(.system(size: (side ?? 120) / 4, weight: .light)).foregroundStyle(Theme.dim)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: (side ?? 190) > 100 ? 14 : 10, style: .continuous))
            .shadow(color: tint.opacity(0.45), radius: (side ?? 190) > 100 ? 20 : 10, y: 6)
        if let side {
            square.frame(width: side, height: side)
        } else {
            square.frame(maxWidth: 190, maxHeight: 190)
        }
    }
}

private struct PlayerColumn: View {
    @EnvironmentObject var media: MediaController
    let now: NowPlaying
    let tint: Color
    var inlineArt = false
    @State private var volume: Double = 50
    @State private var editingVolume = false

    var body: some View {
        let shown = Lyrics.clean(title: now.title, artist: now.artist)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if inlineArt {
                    Artwork(tint: tint, side: 64)
                }
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Equalizer(playing: now.playing, count: 4, color: tint)
                        Text(now.app).font(.app(size: 9, weight: .semibold)).foregroundStyle(tint).lineLimit(1)
                    }
                    Text(shown.0.isEmpty ? now.title : shown.0)
                        .font(.app(size: inlineArt ? 15 : 18, weight: .bold)).lineLimit(2)
                        .padding(.top, 5)
                    Text(shown.1.isEmpty ? now.album : shown.1)
                        .font(.app(size: 11)).foregroundStyle(Theme.dim).lineLimit(1)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 10)

            TimelineView(.periodic(from: .now, by: now.playing ? 1 : 3600)) { context in
                let position = now.position(at: context.date)
                VStack(spacing: 4) {
                    ProgressTrack(value: now.duration > 0 ? position / now.duration : 0, color: tint) {
                        media.seek($0 * now.duration)
                    }
                    HStack {
                        Text(formatClock(position))
                        Spacer()
                        Text("-" + formatClock(max(0, now.duration - position)))
                    }
                    .font(.mono(size: 8.5))
                    .foregroundStyle(Theme.faint)
                }
            }

            HStack(spacing: 6) {
                control("backward.end.fill", "Previous") { media.previous() }
                control("gobackward.15", "Back 15 seconds") { media.skip(-15) }
                Button { media.playPause() } label: {
                    Image(systemName: now.playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 40, height: 40)
                        .buttonFace(Circle(), tint)
                        .contentShape(Circle())
                }
                .buttonStyle(PressStyle())
                .help(now.playing ? "Pause" : "Play")
                control("goforward.15", "Forward 15 seconds") { media.skip(15) }
                control("forward.end.fill", "Next") { media.next() }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 8)

            HStack(spacing: 10) {
                Image(systemName: "speaker.fill").font(.system(size: 9)).foregroundStyle(Theme.dim)
                Slider(value: $volume, in: 0...100) { editing in
                    editingVolume = editing
                    if !editing { media.setVolume(volume) }
                }
                .controlSize(.mini)
                .tint(tint)
                Image(systemName: "speaker.wave.3.fill").font(.system(size: 9)).foregroundStyle(Theme.dim)
                SleepMenu()
                OutputMenu()
            }
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { volume = media.volume }
        .onChange(of: media.volume) { _, v in if !editingVolume { volume = v } }
    }

    private func control(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 30, height: 30)
                .buttonFace(Circle(), Theme.ink.opacity(0.09))
                .contentShape(Circle())
        }
        .buttonStyle(PressStyle())
        .help(label)
    }
}

private struct OutputMenu: View {
    @EnvironmentObject var audio: AudioOutputMonitor

    var body: some View {
        Menu {
            ForEach(audio.devices) { device in
                Button {
                    audio.select(device)
                } label: {
                    if device.id == audio.current {
                        Label(device.name, systemImage: "checkmark")
                    } else {
                        Text(device.name)
                    }
                }
            }
        } label: {
            Image(systemName: audio.currentName.localizedCaseInsensitiveContains("airpods") ? "airpodspro" : "hifispeaker.fill")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sound output: \(audio.currentName)")
    }
}

// Pauses whatever is playing after a while; the icon fills in while it counts down.
private struct SleepMenu: View {
    @EnvironmentObject var media: MediaController

    var body: some View {
        Menu {
            ForEach([15, 30, 45, 60], id: \.self) { m in
                Button("Pause in \(m) min") { media.setSleep(minutes: m) }
            }
            if let end = media.sleepAt {
                Divider()
                Button("Turn off (pauses at \(end.formatted(date: .omitted, time: .shortened)))") { media.setSleep(minutes: nil) }
            }
        } label: {
            Image(systemName: media.sleepAt == nil ? "moon.zzz" : "moon.zzz.fill")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(media.sleepAt == nil ? Theme.dim : Theme.accent)
        .help(media.sleepAt == nil ? "Sleep timer" : "Sleep timer is on")
    }
}

private struct LyricsColumn: View {
    @EnvironmentObject var lyrics: Lyrics
    let now: NowPlaying
    let tint: Color

    var body: some View {
        Group {
            if lyrics.state == .loading {
                LoadingView(text: "Finding lyrics…")
            } else if lyrics.state == .synced {
                TimelineView(.periodic(from: .now, by: now.playing ? 0.5 : 3600)) { context in
                    let current = lyrics.index(at: now.position(at: context.date))
                    // Two lines either side of the one being sung, the far ones fading into the card.
                    VStack(alignment: .leading, spacing: 9) {
                        line(current.map { $0 - 2 }, size: 10.5, color: Theme.ink.opacity(0.2))
                        line(current.map { $0 - 1 }, size: 11, color: Theme.faint)
                        line(current, size: 14, color: tint, bold: true, empty: "♪")
                        line((current ?? -1) + 1, size: 11, color: Theme.dim)
                        line((current ?? -1) + 2, size: 10.5, color: Theme.faint)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .transaction { $0.animation = nil }
                }
            } else {
                ScrollView {
                    Text(lyrics.plain).font(.app(size: 10.5)).foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
            }
        }
        .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                                     .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                             startPoint: .top, endPoint: .bottom))
        .overlay(alignment: .bottomTrailing) {
            Text("LRCLIB · NetEase · QQ · Kugou").font(.app(size: 7.5, weight: .semibold)).foregroundStyle(Theme.faint)
        }
    }

    @ViewBuilder private func line(_ index: Int?, size: CGFloat, color: Color, bold: Bool = false, empty: String = " ") -> some View {
        let text = index.flatMap { lyrics.lines.indices.contains($0) ? lyrics.lines[$0].text : nil } ?? empty
        Text(text)
            .font(.app(size: size, weight: bold ? .bold : .regular))
            .foregroundStyle(color)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct ProgressTrack: View {
    var value: Double
    var color: Color
    var onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.ink.opacity(0.12))
                Capsule().fill(color).frame(width: geo.size.width * min(max(value, 0), 1))
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onEnded { g in
                onSeek(min(max(g.location.x / geo.size.width, 0), 1))
            })
        }
        .frame(height: 12)
    }
}
