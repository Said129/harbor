import SwiftUI

@main
struct HarborApp: App {
    @State private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            HarborShell(app: model).font(.custom("Inter-Regular", size: 16, relativeTo: .body)).tint(HarborTheme.accent).preferredColorScheme(.dark)
                .task { await model.start() }
                .sheet(isPresented: $model.showAccount) { NavigationStack { AccountView(app: model) } }
        }
    }
}
