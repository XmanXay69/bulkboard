import SwiftUI

struct BodyView: View {
    var profile: ProfileRecord

    var body: some View {
        EmptyStateView(symbol: "figure.arms.open", title: "Body & Dunk", message: "Coming next.")
    }
}
