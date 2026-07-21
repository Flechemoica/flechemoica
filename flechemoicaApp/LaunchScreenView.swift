import SwiftUI

struct LaunchScreenView: View {
    @Binding var isComplete: Bool
    @State private var progress = 0.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 24) {
                    XPLogoView(size: 142)

                    Text("FLÈCHE-MOI ÇA")
                        .font(.system(size: 34, weight: .black).italic())
                        .tracking(0)
                        .foregroundStyle(.white)

                    XPProgressBar(progress: progress)
                        .frame(width: 236, height: 22)
                        .padding(.top, 10)
                }

                Spacer()

                Text("© 2026 Flèche-moi ça")
                    .font(.custom("Tahoma", size: 12))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.bottom, 26)
            }
            .padding(.horizontal, 24)
        }
        .task {
            await runLaunchAnimation()
        }
    }

    private func runLaunchAnimation() async {
        progress = 0

        for step in 1...34 {
            try? await Task.sleep(for: .milliseconds(55))
            progress = min(Double(step) / 34.0, 1)
        }

        try? await Task.sleep(for: .milliseconds(260))
        isComplete = true
    }
}

struct XPProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            let filledWidth = max(0, proxy.size.width * progress)
            let segmentWidth: CGFloat = 12
            let segmentCount = Int(proxy.size.width / segmentWidth)

            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white)

                HStack(spacing: 3) {
                    ForEach(0..<segmentCount, id: \.self) { index in
                        let x = CGFloat(index) * segmentWidth
                        Rectangle()
                            .fill(Color(red: 0.05, green: 0.28, blue: 0.88))
                            .frame(width: 9)
                            .opacity(x < filledWidth ? 1 : 0)
                    }
                }
                .padding(3)
            }
            .overlay(Rectangle().stroke(Color(red: 0.48, green: 0.48, blue: 0.48), lineWidth: 1))
        }
    }
}

#Preview {
    LaunchScreenView(isComplete: .constant(false))
}
