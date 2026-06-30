import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var persistence: PersistenceController

    @State private var showResetConfirm = false
    @State private var showResetDone = false
    @State private var isResyncing = false
    @State private var showResyncDone = false

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: Info
                Section {
                    LabeledContent(NSLocalizedString("about_version_label", comment: ""), value: version)
                    LabeledContent(NSLocalizedString("about_build_label", comment: ""), value: build)
                } header: {
                    Text(NSLocalizedString("settings_info_section", comment: ""))
                }

                // MARK: Sincronizzazione
                Section {
                    Button {
                        runForceResync()
                    } label: {
                        HStack {
                            Label(NSLocalizedString("settings_force_resync", comment: ""),
                                  systemImage: "arrow.clockwise.icloud")
                            if isResyncing {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isResyncing)

                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Label(NSLocalizedString("settings_reset_sync", comment: ""),
                              systemImage: "arrow.triangle.2.circlepath")
                    }
                } header: {
                    Text(NSLocalizedString("settings_sync_section", comment: ""))
                } footer: {
                    Text(NSLocalizedString("settings_reset_sync_footer", comment: ""))
                }
            }
            .navigationTitle(NSLocalizedString("settings_title", comment: ""))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Fine", comment: "")) { dismiss() }
                }
            }
            .confirmationDialog(
                NSLocalizedString("settings_reset_sync_confirm_title", comment: ""),
                isPresented: $showResetConfirm,
                titleVisibility: .visible
            ) {
                Button(NSLocalizedString("settings_reset_sync_confirm_action", comment: ""), role: .destructive) {
                    persistence.requestSyncReset()
                    showResetDone = true
                }
                Button(NSLocalizedString("Annulla", comment: ""), role: .cancel) {}
            } message: {
                Text(NSLocalizedString("settings_reset_sync_confirm_message", comment: ""))
            }
            .alert(
                NSLocalizedString("settings_force_resync_done_title", comment: ""),
                isPresented: $showResyncDone
            ) {
                Button(NSLocalizedString("Fine", comment: "")) { dismiss() }
            } message: {
                Text(NSLocalizedString("settings_force_resync_done_message", comment: ""))
            }
            .alert(
                NSLocalizedString("settings_reset_done_title", comment: ""),
                isPresented: $showResetDone
            ) {
                Button(NSLocalizedString("Fine", comment: "")) {
                    // Niente exit(0) (sembrerebbe un crash): lo store verrà
                    // ricreato pulito al prossimo avvio manuale dell'app.
                    dismiss()
                }
            } message: {
                Text(NSLocalizedString("settings_reset_done_message", comment: ""))
            }
        }
    }

    private func runForceResync() {
        isResyncing = true
        persistence.forceResync {
            // Lascia un attimo alla sync per assestarsi dopo il ricaricamento.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                isResyncing = false
                showResyncDone = true
            }
        }
    }
}
