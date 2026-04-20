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
    static func make(
        text: String,
        textColor: NSColor,
        font: NSFont
    ) -> NSTextField {
        let textField = NSTextField(wrappingLabelWithString: text)
        configure(textField, text: text, textColor: textColor, font: font)
        return textField
    }

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
