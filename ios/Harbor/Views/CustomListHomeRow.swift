import SwiftUI

struct CustomListItemDestination: View {
    let app: AppModel
    let item: CustomListItem
    let listID: String
    var playImmediately = false
    var body: some View {
        if item.type == "manga" { CustomListMangaDestination(app: app, item: item, listID: listID, readImmediately: playImmediately) }
        else { DetailView(media: item.media, app: app, playImmediately: playImmediately) }
    }
}

struct CustomListScreen: View {
    let app: AppModel
    let listID: String
    var body: some View {
        ScrollView { CustomListsContent(app: app, initialListID: listID).padding() }
            .background(HarborTheme.background).navigationTitle(DesktopInterfaceText.value("My lists"))
            .navigationBarTitleDisplayMode(.inline).toolbar(.visible, for: .navigationBar)
    }
}

struct CustomListHomeRow: View {
    let list: CustomList
    let title: String
    let app: AppModel
    var ranked = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(HarborTheme.font(17, weight: .medium)).accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("home-list-title-" + list.id)
                Spacer()
                NavigationLink { CustomListScreen(app: app, listID: list.id) } label: {
                    Label(DesktopInterfaceText.value("View all"), image: "desktop-chevron-right").font(.caption).foregroundStyle(.secondary).frame(minHeight: 44)
                }.accessibilityIdentifier("home-list-browse-" + list.id)
            }.padding(.horizontal)
            if ranked && list.items.count >= 10 { TopTenRail(metas: list.items.map(\.media), app: app, customList: list) }
            else {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(list.items) { item in
                            NavigationLink { CustomListItemDestination(app: app, item: item, listID: list.id) } label: { Poster(media: item.media) }
                                .buttonStyle(.plain).accessibilityLabel(item.name).accessibilityIdentifier("home-list-item")
                        }
                    }.padding(.horizontal)
                }.scrollIndicators(.hidden).posterRowBehavior()
            }
        }
    }
}
