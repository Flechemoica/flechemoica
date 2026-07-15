import SwiftUI

extension Font {
    static func xpTahoma(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Tahoma", size: size).weight(weight)
    }
}

extension Color {
    static let xpBlueTop = Color(red: 0.25, green: 0.57, blue: 1.0)
    static let xpBlueMid = Color(red: 0.02, green: 0.29, blue: 0.82)
    static let xpBlueBottom = Color(red: 0.0, green: 0.19, blue: 0.62)
    static let xpChrome = Color(red: 0.93, green: 0.91, blue: 0.84)
    static let xpPanel = Color(red: 1.0, green: 0.99, blue: 0.94)
    static let xpLavender = Color(red: 0.82, green: 0.76, blue: 1.0)
}

struct XPTitleBar: View {
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            XPLogoView(size: 24)
            Text(title)
                .font(.xpTahoma(size: 17, weight: .bold))
                .lineLimit(1)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.65), radius: 0, x: 1, y: 1)

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                XPWindowButton(kind: .minimize)
                XPWindowButton(kind: .maximize)
                XPWindowButton(kind: .close)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(
            LinearGradient(colors: [.xpBlueTop, .xpBlueMid, .xpBlueBottom],
                           startPoint: .top,
                           endPoint: .bottom)
        )
    }
}

struct XPWindowButton: View {
    enum Kind {
        case minimize
        case maximize
        case close
    }

    let kind: Kind

    private var isClose: Bool {
        kind == .close
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: isClose ? [Color.orange.opacity(0.95), .red] : [Color(red: 0.48, green: 0.72, blue: 1.0), .xpBlueMid],
                           startPoint: .top,
                           endPoint: .bottom)

            icon
                .stroke(.white, style: StrokeStyle(lineWidth: 2, lineCap: .square, lineJoin: .miter))
                .frame(width: 11, height: 11)
        }
        .frame(width: 24, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white, lineWidth: 1))
    }

    private var icon: Path {
        var path = Path()

        switch kind {
        case .minimize:
            path.move(to: CGPoint(x: 1, y: 9))
            path.addLine(to: CGPoint(x: 10, y: 9))
        case .maximize:
            path.addRect(CGRect(x: 1.5, y: 1.5, width: 8, height: 8))
        case .close:
            path.move(to: CGPoint(x: 2, y: 2))
            path.addLine(to: CGPoint(x: 9, y: 9))
            path.move(to: CGPoint(x: 9, y: 2))
            path.addLine(to: CGPoint(x: 2, y: 9))
        }

        return path
    }
}

struct XPWindow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            XPTitleBar(title: title)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.xpChrome)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(red: 0.1, green: 0.31, blue: 0.61), lineWidth: 3))
        .shadow(color: .black.opacity(0.45), radius: 20, x: 0, y: 18)
    }
}

struct XPButtonStyle: ButtonStyle {
    var foregroundColor: Color = .black

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.xpTahoma(size: 15, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 18)
            .frame(height: 38)
            .background(
                LinearGradient(colors: configuration.isPressed ? [Color(red: 0.84, green: 0.80, blue: 0.67), .white] : [.white, Color(red: 0.86, green: 0.82, blue: 0.69)],
                               startPoint: .top,
                               endPoint: .bottom)
            )
            .overlay(Rectangle().stroke(Color(red: 0.0, green: 0.24, blue: 0.45), lineWidth: 1))
            .offset(x: configuration.isPressed ? 1 : 0, y: configuration.isPressed ? 1 : 0)
    }
}
