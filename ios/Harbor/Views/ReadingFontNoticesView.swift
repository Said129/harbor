import SwiftUI

struct ReadingFontNoticesView: View {
    private var notice: String {
        guard let url = Bundle.main.url(forResource: "ReadingFontNotices", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }
    var body: some View {
        ScrollView {
            Text(verbatim: notice).font(.callout).textSelection(.enabled)
                .frame(maxWidth: 820, alignment: .leading).frame(maxWidth: .infinity).padding(20)
        }.background(HarborTheme.background).foregroundStyle(HarborTheme.ink)
            .navigationTitle(DesktopInterfaceText.value("Legal")).navigationBarTitleDisplayMode(.inline)
    }
}
