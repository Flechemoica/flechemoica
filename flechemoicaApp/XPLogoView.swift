import SwiftUI

struct XPLogoView: View {
    var size: CGFloat = 132

    var body: some View {
        Image("Logo")
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .frame(width: size, height: size)
            .shadow(color: .black.opacity(0.28), radius: 0, x: 2, y: 2)
            .accessibilityLabel("Logo Flèche-moi ça")
    }
}

#Preview {
    XPLogoView()
        .padding()
        .background(Color.black)
}
