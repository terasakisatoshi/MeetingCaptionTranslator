import SwiftUI

struct OverlayView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(viewModel.rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.sourceText)
                        .font(.system(size: viewModel.fontSize, weight: .semibold))
                        .foregroundStyle(.white.opacity(row.state == .partial ? 0.74 : 1))

                    if let translatedText = row.translatedText, !translatedText.isEmpty {
                        Text(translatedText)
                            .font(.system(size: max(14, viewModel.fontSize - 4), weight: .regular))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                }
            }

            if viewModel.rows.isEmpty {
                Text(viewModel.statusText)
                    .font(.system(size: max(14, viewModel.fontSize - 2), weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.black.opacity(viewModel.overlayOpacity))
        )
        .padding(18)
    }
}
