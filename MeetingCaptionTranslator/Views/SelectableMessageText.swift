import AppKit
import SwiftUI

struct SelectableMessageText: NSViewRepresentable {
    let text: String
    let textColor: NSColor
    let font: NSFont

    init(
        _ text: String,
        textColor: NSColor = .labelColor,
        font: NSFont = .preferredFont(forTextStyle: .callout)
    ) {
        self.text = text
        self.textColor = textColor
        self.font = font
    }

    func makeNSView(context: Context) -> NSTextField {
        SelectableMessageTextField.make(
            text: text,
            textColor: textColor,
            font: font
        )
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        SelectableMessageTextField.configure(
            nsView,
            text: text,
            textColor: textColor,
            font: font
        )
    }
}

enum SelectableMessageTextField {
    @MainActor
    static func make(
        text: String,
        textColor: NSColor,
        font: NSFont
    ) -> NSTextField {
        let textField = NSTextField(wrappingLabelWithString: text)
        configure(textField, text: text, textColor: textColor, font: font)
        return textField
    }

    @MainActor
    static func configure(
        _ textField: NSTextField,
        text: String,
        textColor: NSColor,
        font: NSFont
    ) {
        textField.stringValue = text
        textField.textColor = textColor
        textField.font = font
        textField.isEditable = false
        textField.isSelectable = true
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.backgroundColor = .clear
        textField.usesSingleLineMode = false
        textField.maximumNumberOfLines = 0
        textField.lineBreakMode = .byWordWrapping
        textField.allowsEditingTextAttributes = false
        textField.focusRingType = .none
        textField.setContentCompressionResistancePriority(.required, for: .vertical)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
    }
}

struct OverlayTranscriptDocument {
    static func make(
        rows: [OverlayRow],
        fontSize: Double,
        statusText: String
    ) -> NSAttributedString {
        let document = NSMutableAttributedString()

        if rows.isEmpty {
            document.append(
                NSAttributedString(
                    string: statusText,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: max(14, fontSize - 2), weight: .medium),
                        .foregroundColor: NSColor.white.withAlphaComponent(0.8)
                    ]
                )
            )
            return document
        }

        for (index, row) in rows.enumerated() {
            if index > 0 {
                document.append(NSAttributedString(string: "\n\n"))
            }

            document.append(
                NSAttributedString(
                    string: row.sourceText,
                    attributes: [
                        .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                        .foregroundColor: NSColor.white.withAlphaComponent(row.state == .partial ? 0.74 : 1)
                    ]
                )
            )

            if let translatedText = row.translatedText, !translatedText.isEmpty {
                document.append(NSAttributedString(string: "\n"))
                document.append(
                    NSAttributedString(
                        string: translatedText,
                        attributes: [
                            .font: NSFont.systemFont(ofSize: max(14, fontSize - 4), weight: .regular),
                            .foregroundColor: NSColor.white.withAlphaComponent(0.92)
                        ]
                    )
                )
            }
        }

        return document
    }
}

enum OverlayTranscriptTextViewComponents {
    @MainActor
    static func make() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 20, height: 20)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.minSize = .zero
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.focusRingType = .none

        scrollView.documentView = textView
        return scrollView
    }

    @MainActor
    static func configure(
        _ scrollView: NSScrollView,
        document: NSAttributedString,
        autoScrollToBottom: Bool = true
    ) {
        guard let textView = scrollView.documentView as? NSTextView else {
            return
        }

        textView.textStorage?.setAttributedString(document)
        if autoScrollToBottom {
            textView.scrollRangeToVisible(NSRange(location: document.length, length: 0))
        }
    }
}

struct OverlayTranscriptTextView: NSViewRepresentable {
    let rows: [OverlayRow]
    let fontSize: Double
    let statusText: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = OverlayTranscriptTextViewComponents.make()
        OverlayTranscriptTextViewComponents.configure(
            scrollView,
            document: OverlayTranscriptDocument.make(
                rows: rows,
                fontSize: fontSize,
                statusText: statusText
            )
        )
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        OverlayTranscriptTextViewComponents.configure(
            nsView,
            document: OverlayTranscriptDocument.make(
                rows: rows,
                fontSize: fontSize,
                statusText: statusText
            )
        )
    }
}
