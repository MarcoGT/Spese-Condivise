import SwiftUI

struct SyncOverlay: View {
    var body: some View {
        ZStack {
                // sfondo scuro trasparente
            Color.black.opacity(0.25)
                .ignoresSafeArea()
            
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                
                Text("Sincronizzazione in corso…")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .padding(20)
            .background(.ultraThinMaterial)
            .cornerRadius(14)
        }
    }
}
