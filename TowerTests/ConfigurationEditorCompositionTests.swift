import SwiftUI
import UIKit
import XCTest
@testable import Tower

/// Issue #22: on the Mac, typing Chinese in the configuration editor left the
/// pinyin behind ("mmemeimei guo…") because highlighting replaced the text
/// while the input method was still composing.
@MainActor
final class ConfigurationEditorCompositionTests: XCTestCase {
    func testHighlightingWaitsForInputMethodComposition() async throws {
        var text = "[General]\n"
        var focused = true
        let binding = Binding(get: { text }, set: { text = $0 })
        let focus = Binding(get: { focused }, set: { focused = $0 })
        let coordinator = ConfigurationEditorTextView.Coordinator(text: binding, isFocused: focus)
        let editor = ConfigurationEditorTextViewFactory.make()
        editor.textView.delegate = coordinator
        coordinator.editor = editor
        ConfigurationEditorTextViewFactory.render(text, in: editor)
        coordinator.renderedText = text

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        window.addSubview(editor)
        editor.frame = window.bounds
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let textView = editor.textView
        textView.selectedRange = NSRange(location: textView.textStorage.length, length: 0)

        // Composing "mei", as a pinyin input method does, then pausing past
        // the highlight delay.
        textView.setMarkedText("mei", selectedRange: NSRange(location: 3, length: 0))
        coordinator.textViewDidChange(textView)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNotNil(textView.markedTextRange, "highlighting ended the composition")

        // Choosing the candidate replaces the pinyin; nothing of it remains.
        textView.setMarkedText("美", selectedRange: NSRange(location: 1, length: 0))
        textView.unmarkText()
        coordinator.textViewDidChange(textView)
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertEqual(textView.text, "[General]\n美")
        XCTAssertEqual(text, "[General]\n美")
    }
}
