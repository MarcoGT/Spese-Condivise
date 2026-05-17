import SwiftUI

struct OnboardingView: View {

    @Binding var isPresented: Bool
    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            systemImage: "rectangle.stack.fill",
            imageColor: .blue,
            title: NSLocalizedString("onboarding_p1_title", comment: ""),
            body: NSLocalizedString("onboarding_p1_body", comment: "")
        ),
        OnboardingPage(
            systemImage: "person.2.fill",
            imageColor: .indigo,
            title: NSLocalizedString("onboarding_p2_title", comment: ""),
            body: NSLocalizedString("onboarding_p2_body", comment: "")
        ),
        OnboardingPage(
            systemImage: "arrow.triangle.2.circlepath",
            imageColor: .green,
            title: NSLocalizedString("onboarding_p3_title", comment: ""),
            body: NSLocalizedString("onboarding_p3_body", comment: "")
        )
    ]

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // Pages
                TabView(selection: $currentPage) {
                    ForEach(pages.indices, id: \.self) { index in
                        OnboardingPageView(page: pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: currentPage)

                // Dots + button
                VStack(spacing: 28) {
                    // Dot indicators
                    HStack(spacing: 8) {
                        ForEach(pages.indices, id: \.self) { index in
                            Capsule()
                                .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                                .frame(width: index == currentPage ? 20 : 8, height: 8)
                                .animation(.spring(response: 0.3), value: currentPage)
                        }
                    }

                    // Button
                    Button {
                        if currentPage < pages.count - 1 {
                            withAnimation { currentPage += 1 }
                        } else {
                            isPresented = false
                        }
                    } label: {
                        Text(currentPage < pages.count - 1
                             ? NSLocalizedString("onboarding_next", comment: "")
                             : NSLocalizedString("onboarding_start", comment: ""))
                            .font(.body)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .padding(.horizontal, 32)
                    .animation(.easeInOut, value: currentPage)
                }
                .padding(.bottom, 48)
            }
        }
    }
}

// MARK: - Page model

private struct OnboardingPage {
    let systemImage: String
    let imageColor: Color
    let title: String
    let body: String
}

// MARK: - Single page layout

private struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            ZStack {
                Circle()
                    .fill(page.imageColor.opacity(0.12))
                    .frame(width: 140, height: 140)
                Image(systemName: page.systemImage)
                    .font(.system(size: 60, weight: .medium))
                    .foregroundColor(page.imageColor)
            }

            VStack(spacing: 16) {
                Text(page.title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)

                Text(page.body)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 32)
            }

            Spacer()
            Spacer()
        }
    }
}
