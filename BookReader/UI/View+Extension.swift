import SwiftUI

extension View {
    func glassCircleButton(
        diameter: CGFloat = 44,
        foreground: Color = .primary,
        background: some ShapeStyle = .tint,
        applyGlass: Bool = true,
        borderWidth: CGFloat = 1,
        borderColor: Color? = nil
    )
        -> some View
    {
        self
            .foregroundStyle(foreground)
            .frame(width: diameter, height: diameter)
            .if(applyGlass) { v in
                v.background(background.opacity(0.5))
                    .glassEffect(.clear.interactive())
            }
            .if(!applyGlass) { v in
                v.background(Circle().fill(.clear))
            }
            .contentShape(Circle())
            .clipShape(Circle())
    }

    func actionIcon(font: Font = .title2) -> some View {
        self
            .font(font)
            .contentTransition(.symbolEffect(.replace))
    }

    @ViewBuilder
    func `if`<Transformed: View>(
        _ condition: Bool,
        transform: (Self) -> Transformed
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

}
