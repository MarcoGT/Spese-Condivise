import SwiftUI

struct NameSetupView: View {

    @EnvironmentObject private var currentUser: CurrentUser
    @State private var nameInput = ""
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 32) {
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 140, height: 140)
                        Image(systemName: "person.fill")
                            .font(.system(size: 60, weight: .medium))
                            .foregroundColor(.accentColor)
                    }

                    VStack(spacing: 12) {
                        Text(NSLocalizedString("name_setup_title", comment: ""))
                            .font(.title2)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                        Text(NSLocalizedString("name_setup_body", comment: ""))
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, 32)
                    }

                    TextField(
                        NSLocalizedString("name_setup_placeholder", comment: ""),
                        text: $nameInput
                    )
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .font(.body)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color(.secondarySystemGroupedBackground))
                    .cornerRadius(12)
                    .padding(.horizontal, 32)
                    .focused($focused)
                    .onSubmit { saveName() }
                }

                Spacer()

                VStack(spacing: 28) {
                    Button(action: saveName) {
                        Text(NSLocalizedString("name_setup_cta", comment: ""))
                            .font(.body)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(nameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        ? Color.accentColor.opacity(0.4)
                                        : Color.accentColor)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .disabled(nameInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .padding(.horizontal, 32)
                    .animation(.easeInOut(duration: 0.2), value: nameInput.isEmpty)
                }
                .padding(.bottom, 48)
            }
        }
        .onAppear { focused = true }
    }

    private func saveName() {
        let trimmed = nameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        currentUser.setName(trimmed)
    }
}
