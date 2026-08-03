import SwiftUI
import UIKit

enum ConfigurationPreviewFormatter {
    static let summaryLineLimit = 18
    static let maximumSummaryLineLength = 480

    static func summary(from content: String) -> String {
        content
            .components(separatedBy: .newlines)
            .prefix(summaryLineLimit)
            .map { line in
                guard line.count > maximumSummaryLineLength else { return line }
                return String(line.prefix(maximumSummaryLineLength)) + " …"
            }
            .joined(separator: "\n")
    }
}

@MainActor
enum ConfigurationTextViewFactory {
    static func make() -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.backgroundColor = .clear
        textView.textColor = .label
        textView.contentInsetAdjustmentBehavior = .never
        textView.textContainerInset = UIEdgeInsets(top: 14, left: 10, bottom: 14, right: 10)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.layoutManager.allowsNonContiguousLayout = true
        let baseFont = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: baseFont)
        textView.adjustsFontForContentSizeCategory = true
        return textView
    }
}

struct ConfigurationTextView: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let textView = ConfigurationTextViewFactory.make()
        textView.text = text
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        guard textView.text != text else { return }
        textView.text = text
        textView.setContentOffset(.zero, animated: false)
    }
}
