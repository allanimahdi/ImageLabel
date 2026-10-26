import AppKit
import SwiftUI

/// ImageLabel palette — Powder Blush / Eggshell / aqua blues / Blue Slate.
enum AppTheme {
    // MARK: Raw palette

    static let powderBlush = Color(hex: 0xFFA69E)
    static let eggshell = Color(hex: 0xFAF3DD)
    static let lightBlue = Color(hex: 0xAED9E0)
    static let icyAqua = Color(hex: 0xB8F2E6)
    static let blueSlate = Color(hex: 0x5E6472)

    // MARK: Semantic roles

    /// Window / page background
    static let background = eggshell
    /// Cards, panels, inset surfaces
    static let surface = Color.white.opacity(0.72)
    /// Soft chip / secondary panel fill
    static let surfaceSecondary = icyAqua.opacity(0.55)
    /// Alternate secondary wash
    static let surfaceTertiary = lightBlue.opacity(0.45)
    /// Primary CTA fill
    static let accent = powderBlush
    /// Text and icons on accent fills (readable on blush)
    static let onAccent = blueSlate
    /// Primary body text / icon stroke
    static let text = blueSlate
    /// Secondary / muted text
    static let textSecondary = blueSlate.opacity(0.72)
    /// Tertiary / path captions
    static let textTertiary = blueSlate.opacity(0.5)
    /// Borders and hairlines
    static let border = blueSlate.opacity(0.28)
    /// Stronger border for primary cards
    static let borderStrong = powderBlush.opacity(0.65)
    /// Success checkmarks
    static let success = Color(hex: 0x3D7A6A)
    /// Warning / credential hints
    static let warning = Color(hex: 0xB86B3A)

    static var atmosphereGradient: LinearGradient {
        LinearGradient(
            colors: [
                eggshell,
                lightBlue.opacity(0.35),
                icyAqua.opacity(0.4),
                powderBlush.opacity(0.18)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

extension View {
    /// Eggshell page wash + Blue Slate as the default tint for controls.
    func appThemedChrome() -> some View {
        self
            .tint(AppTheme.accent)
            .foregroundStyle(AppTheme.text)
            .background(AppTheme.background.ignoresSafeArea())
    }
}

/// Filled Powder Blush CTA with slate label.
struct AppPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(AppTheme.onAccent.opacity(isEnabled ? 1 : 0.45))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.accent.opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(AppTheme.blueSlate.opacity(0.15), lineWidth: 1)
            }
    }
}
