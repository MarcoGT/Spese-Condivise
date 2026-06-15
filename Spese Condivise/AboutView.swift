import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var appName: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "Spese Condivise"
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // App header
                VStack(spacing: 12) {
                    Image(systemName: "eurosign.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.green)
                        .padding(.top, 32)

                    Text(appName)
                        .font(.title2.weight(.bold))

                    Text(String(format: NSLocalizedString("about_version_format", comment: ""), version, build))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 24)

                Form {
                    Section {
                        LabeledContent(NSLocalizedString("about_version_label", comment: ""), value: version)
                        LabeledContent(NSLocalizedString("about_build_label", comment: ""), value: build)
                    }

                    Section {
                        Text(NSLocalizedString("about_footer", comment: ""))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle(NSLocalizedString("about_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Fine", comment: "")) { dismiss() }
                }
            }
        }
    }
}
