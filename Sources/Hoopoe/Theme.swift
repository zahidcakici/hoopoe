import AppKit
import SwiftUI

enum Theme {
    /// Warm orange, after the bird. Lighter in dark mode so it keeps its contrast.
    static let accent = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.96, green: 0.58, blue: 0.27, alpha: 1)
            : NSColor(srgbRed: 0.84, green: 0.42, blue: 0.13, alpha: 1)
    })
}

extension View {
    func card(padding: CGFloat = 14) -> some View {
        self.padding(padding)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Small uppercase heading used above groups of content.
    func sectionLabel() -> some View {
        font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.4)
    }
}

/// Borderless icon button with a hover highlight.
struct IconButton: View {
    let symbol: String
    let help: String
    var tint: Color = .secondary
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(Color.primary.opacity(hovering ? 0.08 : 0), in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
