import SwiftUI

struct TextFieldDialog: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let onCancel: () -> Void
    let onSave: () -> Void
    let topOffset: CGFloat = 120

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack {
                VStack(spacing: 16) {
                    Text(title)
                        .font(.headline)
                    TextField(placeholder, text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(10)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    HStack {
                        Button("取消") {
                            onCancel()
                        }
                        .frame(maxWidth: .infinity)
                        Button("保存") {
                            onSave()
                        }
                        .frame(maxWidth: .infinity)
                        .disabled(
                            text.trimmingCharacters(in: .whitespacesAndNewlines)
                                .isEmpty
                        )
                    }
                }
                .padding(20)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 40)
                .padding(.top, topOffset)

                Spacer()
            }
        }
    }
}
