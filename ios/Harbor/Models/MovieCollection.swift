import Foundation

struct MovieCollection: Identifiable, Sendable {
    let id: Int
    let name: String
    let description: String?
    let poster: String?
    let background: String?
}
struct CollectionPage: Sendable {
    let items: [MovieCollection]
    let totalPages: Int
}
struct CollectionDetails: Sendable {
    let name: String
    let description: String?
    let background: String?
    let parts: [Media]
}
