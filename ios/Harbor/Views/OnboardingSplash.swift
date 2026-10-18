import SwiftUI

struct OnboardingSplash: View {
    let app: AppModel
    let advance: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var posters: [Media] = []
    @State private var started = Date()
    @State private var appeared = false
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
                            VStack(spacing: 12) {
                                ForEach(0..<16, id: \.self) { index in
                                    let media = posters.isEmpty ? nil : posters[(column * 8 + index % 8) % posters.count]
                                    Artwork(url: media?.poster, maxPixels: 240, showsPlaceholder: false)
                                        .frame(width: width, height: width * 1.5).background(HarborTheme.surface)
                                        .clipShape(.rect(cornerRadius: 6))
                                }
                            }.offset(y: -CGFloat(column.isMultiple(of: 2) ? phase : 1 - phase) * stripHeight)
                        }
                    }.padding(.horizontal, 8).opacity(0.55).frame(height: geometry.size.height, alignment: .top).clipped()
                }.accessibilityHidden(true)
                RadialGradient(colors: [.black.opacity(0.55), .black.opacity(0.85), .black.opacity(0.96)], center: .center, startRadius: 0, endRadius: max(geometry.size.width, geometry.size.height) * 0.65)
                VStack(spacing: 16) {
                    HarborBrand(size: min(geometry.size.width / 6, 76), tiltedO: true)
                    Text(DesktopInterfaceText.value("Built for Adventure!").uppercased()).font(HarborTheme.font(12, weight: .medium)).tracking(3.5).foregroundStyle(.secondary)
                }.opacity(appeared ? 1 : 0).scaleEffect(appeared || reduceMotion ? 1 : 0.9)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.7), value: appeared)
            }.clipped()
        }.accessibilityIdentifier("guide-splash")
            .onAppear { appeared = true }
            .task {
                let available = app.rows.flatMap(\.metas).filter { $0.poster?.isEmpty == false }
                if !available.isEmpty { posters = Array(available.prefix(40)); return }
                do { posters = try await OnboardingContent().splash(service: app.service) } catch { }
            }
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                do { try await Task.sleep(for: .milliseconds(2600)); try Task.checkCancellation(); advance() } catch { }
            }
    }
}
