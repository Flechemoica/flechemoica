import SwiftUI
import UIKit

struct SecurePasswordTextField: UIViewRepresentable {
    @Binding var text: String

    let placeholder: String
    var textContentType: UITextContentType? = .password

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.isSecureTextEntry = true
        textField.textContentType = textContentType
        textField.passwordRules = passwordRules
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
        uiView.passwordRules = passwordRules
        uiView.attributedPlaceholder = placeholderText
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    private var passwordRules: UITextInputPasswordRules? {
        guard textContentType == .newPassword else { return nil }
        return UITextInputPasswordRules(descriptor: "minlength: 12; maxlength: 64;")
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

        func textFieldDidChangeSelection(_ textField: UITextField) {
            text = textField.text ?? ""
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            text = textField.text ?? ""
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            guard let currentText = textField.text,
                  let textRange = Range(range, in: currentText) else {
                return true
            }

            text = currentText.replacingCharacters(in: textRange, with: string)
            return true
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}
