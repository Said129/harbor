import SwiftUI

struct OnboardingSplash: View {
    let app: AppModel
    let advance: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var posters: [Media] = []
    @State private var started = Date()
    @State private var appeared = false
    @State private var leaving = false
    private let speeds = [22.0, 32, 26, 38, 30]
    private let delays = [5.0, 14, 3, 19, 9]
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || scenePhase != .active)) { context in
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(0..<5, id: \.self) { column in
                            let width = max(1, (geometry.size.width - 48) / 5)
                            let stripHeight = (width * 1.5 + 12) * 8
                            let elapsed = reduceMotion ? 0 : max(0, context.date.timeIntervalSince(started))
                            let phase = ((elapsed + delays[column]) / speeds[column]).truncatingRemainder(dividingBy: 1)
                            let urls = (0..<16).map { index in posters.isEmpty ? nil : posters[(column * 8 + index % 8) % posters.count].poster }
                            SplashPosterStrip(urls: urls, width: width).equatable()
                                .offset(y: -CGFloat(column.isMultiple(of: 2) ? phase : 1 - phase) * stripHeight)
                        }
                    }.padding(.horizontal, 8).opacity(0.55).frame(height: geometry.size.height, alignment: .top).clipped()
                }.accessibilityHidden(true)
                RadialGradient(colors: [.black.opacity(0.55), .black.opacity(0.85), .black.opacity(0.96)], center: .center, startRadius: 0, endRadius: max(geometry.size.width, geometry.size.height) * 0.65)
                VStack(spacing: 16) {
                    HarborBrand(size: min(geometry.size.width / 6, 76), tiltedO: true)
                        .opacity(appeared ? 1 : 0).scaleEffect(appeared || reduceMotion ? 1 : 0.96).offset(y: appeared || reduceMotion ? 0 : 12)
                        .animation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.760), value: appeared)
                    Text(DesktopInterfaceText.value("Built for Adventure!").uppercased()).font(HarborTheme.font(12, weight: .medium)).tracking(3.5).foregroundStyle(.secondary)
                        .opacity(appeared ? 1 : 0).scaleEffect(appeared || reduceMotion ? 1 : 0.96).offset(y: appeared || reduceMotion ? 0 : 12)
                        .animation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.760).delay(0.260), value: appeared)
                }
            }.clipped().opacity(leaving ? 0 : 1)
                .animation(reduceMotion ? nil : .timingCurve(0.16, 1, 0.3, 1, duration: 0.380), value: leaving)
        }.accessibilityIdentifier("guide-splash")
            .onAppear { appeared = true }
            .task {
                let available = app.rows.flatMap(\.metas).filter { $0.poster?.isEmpty == false }
                if !available.isEmpty { posters = Array(available.prefix(40)); return }
                do { posters = try await OnboardingContent().splash(service: app.service) } catch { }
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                withTransaction(Transaction(animation: nil)) { leaving = false }
                do {
                    try await Task.sleep(for: .milliseconds(2220)); try Task.checkCancellation(); leaving = true
                    try await Task.sleep(for: .milliseconds(380)); try Task.checkCancellation(); advance()
                } catch { }
            }
    }
}

/// Only the column transform changes on animation frames. Keep each artwork
/// subtree stable until its URLs or geometry actually change.
private struct SplashPosterStrip: View, Equatable {
    let urls: [String?]
    let width: CGFloat
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.urls == rhs.urls && lhs.width == rhs.width }
    var body: some View {
        VStack(spacing: 12) {
            ForEach(urls.indices, id: \.self) { index in
                Artwork(url: urls[index], maxPixels: 240, showsPlaceholder: false)
                    .frame(width: width, height: width * 1.5).background(HarborTheme.surface)
                    .clipShape(.rect(cornerRadius: 6))
            }
        }
    }
}
