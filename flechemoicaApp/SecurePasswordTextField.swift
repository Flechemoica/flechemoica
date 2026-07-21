import SwiftUI
import UIKit

final class PasteDisabledTextInput: UITextField {
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        let blockedActions: [Selector] = [
            #selector(UIResponderStandardEditActions.copy(_:)),
            #selector(UIResponderStandardEditActions.cut(_:)),
            #selector(UIResponderStandardEditActions.paste(_:)),
            #selector(UIResponderStandardEditActions.select(_:)),
            #selector(UIResponderStandardEditActions.selectAll(_:))
        ]

        if blockedActions.contains(action) {
            return false
        }

        return super.canPerformAction(action, withSender: sender)
    }
}

struct PasteDisabledTextField: UIViewRepresentable {
    @Binding var text: String

    let placeholder: String
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?

    func makeUIView(context: Context) -> UITextField {
        let textField = PasteDisabledTextInput(frame: .zero)
        textField.delegate = context.coordinator
        textField.keyboardType = keyboardType
        textField.textContentType = textContentType
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.spellCheckingType = .no
        textField.smartDashesType = .no
        textField.smartQuotesType = .no
        textField.smartInsertDeleteType = .no
        textField.returnKeyType = .done
        textField.clearButtonMode = .whileEditing
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.textColor = .black
        textField.tintColor = .black
        textField.font = UIFont(name: "Tahoma", size: 16) ?? .systemFont(ofSize: 16)
        textField.attributedPlaceholder = placeholderText
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)

        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if !uiView.isFirstResponder && uiView.text != text {
            uiView.text = text
        }

        uiView.keyboardType = keyboardType
        uiView.textContentType = textContentType
        uiView.attributedPlaceholder = placeholderText
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    private var placeholderText: NSAttributedString {
        NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.gray]
        )
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        @objc func textDidChange(_ textField: UITextField) {
            text = textField.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

struct SecurePasswordTextField: UIViewRepresentable {
    @Binding var text: String

    let placeholder: String
    var textContentType: UITextContentType?

    func makeUIView(context: Context) -> UITextField {
        let textField = PasteDisabledTextInput(frame: .zero)
        textField.delegate = context.coordinator
        textField.textContentType = textContentType
        textField.isSecureTextEntry = true
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.spellCheckingType = .no
        textField.smartDashesType = .no
        textField.smartQuotesType = .no
        textField.smartInsertDeleteType = .no
        textField.returnKeyType = .done
        textField.clearButtonMode = .whileEditing
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.textColor = .black
        textField.tintColor = .black
        textField.font = UIFont(name: "Tahoma", size: 16) ?? .systemFont(ofSize: 16)
        textField.attributedPlaceholder = placeholderText
        textField.addTarget(context.coordinator, action: #selector(Coordinator.textDidChange(_:)), for: .editingChanged)

        return textField
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if !uiView.isFirstResponder && uiView.text != text {
            uiView.text = text
        }

        uiView.textContentType = textContentType
        uiView.attributedPlaceholder = placeholderText
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    private var placeholderText: NSAttributedString {
        NSAttributedString(
            string: placeholder,
            attributes: [.foregroundColor: UIColor.gray]
        )
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        @objc func textDidChange(_ textField: UITextField) {
            text = textField.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}
