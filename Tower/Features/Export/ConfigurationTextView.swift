import SwiftUI
import UIKit

enum ConfigurationSyntaxHighlighter {
    enum Accent: Hashable, Sendable {
        case blue
        case purple
        case teal
        case orange
        case pink
        case indigo

        var color: UIColor {
            UIColor { traits in
                let isDark = traits.userInterfaceStyle == .dark
                switch self {
                case .blue:
                    return isDark
                        ? UIColor(red: 0.40, green: 0.65, blue: 1.00, alpha: 1)
                        : UIColor(red: 0.18, green: 0.39, blue: 0.86, alpha: 1)
                case .purple:
                    return isDark
                        ? UIColor(red: 0.78, green: 0.50, blue: 1.00, alpha: 1)
                        : UIColor(red: 0.56, green: 0.23, blue: 0.78, alpha: 1)
                case .teal:
                    return isDark
                        ? UIColor(red: 0.25, green: 0.82, blue: 0.73, alpha: 1)
                        : UIColor(red: 0.00, green: 0.47, blue: 0.42, alpha: 1)
                case .orange:
                    return isDark
                        ? UIColor(red: 1.00, green: 0.65, blue: 0.33, alpha: 1)
                        : UIColor(red: 0.72, green: 0.32, blue: 0.05, alpha: 1)
                case .pink:
                    return isDark
                        ? UIColor(red: 1.00, green: 0.48, blue: 0.68, alpha: 1)
                        : UIColor(red: 0.72, green: 0.18, blue: 0.39, alpha: 1)
                case .indigo:
                    return isDark
                        ? UIColor(red: 0.58, green: 0.58, blue: 1.00, alpha: 1)
                        : UIColor(red: 0.32, green: 0.29, blue: 0.72, alpha: 1)
                }
            }
        }
    }

    enum Style: Hashable, Sendable {
        case comment
        case section(Accent)
        case key(Accent)
        case directive(Accent)
        case string
        case number
        case keyword
        case url
    }

    struct Span: Equatable, Sendable {
        let range: NSRange
        let style: Style
    }

    private static let numberExpression = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9_.-])[-+]?\d+(?:\.\d+)?(?![A-Za-z0-9_.-])"#
    )
    private static let keywordExpression = try! NSRegularExpression(
        pattern: #"\b(?:true|false|null|direct|reject|proxy|block|auto|udp|tcp)\b"#,
        options: .caseInsensitive
    )
    private static let stringExpression = try! NSRegularExpression(
        pattern: #"\"(?:\\.|[^\"\\])*\"|'(?:''|[^'])*'"#
    )
    private static let urlExpression = try! NSRegularExpression(
        pattern: #"https?://[^\s,\]\[<>\"')]+"#,
        options: .caseInsensitive
    )

    static func spans(in text: String) -> [Span] {
        guard !text.isEmpty else { return [] }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var result: [Span] = []

        appendMatches(numberExpression, style: .number, text: text, range: fullRange, to: &result)
        appendMatches(keywordExpression, style: .keyword, text: text, range: fullRange, to: &result)
        appendMatches(stringExpression, style: .string, text: text, range: fullRange, to: &result)
        appendMatches(urlExpression, style: .url, text: text, range: fullRange, to: &result)

        var currentAccent: Accent = .blue
        var location = 0
        while location < nsText.length {
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            nsText.getLineStart(
                &lineStart,
                end: &lineEnd,
                contentsEnd: &contentsEnd,
                for: NSRange(location: location, length: 0)
            )
            guard lineEnd > location else { break }

            let lineRange = NSRange(location: lineStart, length: contentsEnd - lineStart)
            let line = nsText.substring(with: lineRange) as NSString
            let firstContent = line.rangeOfCharacter(from: CharacterSet.whitespaces.inverted)
            guard firstContent.location != NSNotFound else {
                location = lineEnd
                continue
            }

            let trimmed = line.substring(from: firstContent.location)
                .trimmingCharacters(in: .whitespaces)
            let trimmedLength = (trimmed as NSString).length
            let trimmedRange = NSRange(
                location: lineStart + firstContent.location,
                length: trimmedLength
            )

            if isComment(trimmed) {
                result.append(Span(range: trimmedRange, style: .comment))
                location = lineEnd
                continue
            }

            if trimmed.hasPrefix("["),
               let close = trimmed.firstIndex(of: "]") {
                let header = String(trimmed[trimmed.index(after: trimmed.startIndex) ..< close])
                currentAccent = accent(for: header)
                let headerLength = (String(trimmed[...close]) as NSString).length
                result.append(
                    Span(
                        range: NSRange(location: trimmedRange.location, length: headerLength),
                        style: .section(currentAccent)
                    )
                )
                location = lineEnd
                continue
            }

            let commentLocation = inlineCommentLocation(in: line, startingAt: firstContent.location)
            let syntaxEnd = commentLocation ?? (firstContent.location + trimmedLength)
            if let commentLocation {
                result.append(
                    Span(
                        range: NSRange(
                            location: lineStart + commentLocation,
                            length: contentsEnd - lineStart - commentLocation
                        ),
                        style: .comment
                    )
                )
            }

            var workStart = firstContent.location
            if line.character(at: workStart) == 45 {
                workStart += 1
                while workStart < syntaxEnd,
                      isWhitespace(line.character(at: workStart)) {
                    workStart += 1
                }
            }
            guard workStart < syntaxEnd else {
                location = lineEnd
                continue
            }

            let workRange = NSRange(location: workStart, length: syntaxEnd - workStart)
            let work = line.substring(with: workRange) as NSString
            var didStyleKey = false
            if let separator = firstUnquotedSeparator(in: work) {
                let lhs = work.substring(to: separator.location) as NSString
                if let keyRange = trimmedContentRange(in: lhs),
                   isValidKey(lhs.substring(with: keyRange)) {
                    let key = lhs.substring(with: keyRange)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    let isTopLevelMapping = separator.character == 58 && firstContent.location <= 2
                    let semanticAccent = isTopLevelMapping ? topLevelAccent(for: key) : nil
                    if let semanticAccent {
                        currentAccent = semanticAccent
                    }
                    result.append(
                        Span(
                            range: NSRange(
                                location: lineStart + workStart + keyRange.location,
                                length: keyRange.length
                            ),
                            style: .key(semanticAccent ?? currentAccent)
                        )
                    )
                    didStyleKey = true
                }
            }

            if !didStyleKey,
               let directiveRange = directiveRange(in: work) {
                result.append(
                    Span(
                        range: NSRange(
                            location: lineStart + workStart + directiveRange.location,
                            length: directiveRange.length
                        ),
                        style: .directive(currentAccent)
                    )
                )
            }

            location = lineEnd
        }
        return result
    }

    @MainActor
    static func attributedString(for text: String, baseFont: UIFont) -> NSAttributedString {
        attributedString(for: text, spans: spans(in: text), baseFont: baseFont)
    }

    /// Applies spans someone else already computed.
    ///
    /// Scanning a full configuration is the expensive half — tens of thousands
    /// of rule lines and four regular expressions over the whole document —
    /// and it needs no main-actor state, so the full-screen preview computes it
    /// off the main thread while its progress view is on screen. Attributes are
    /// still applied here, because the fonts and dynamic colours they carry are
    /// UIKit objects.
    @MainActor
    static func attributedString(
        for text: String,
        spans: [Span],
        baseFont: UIFont
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 0

        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: baseFont,
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraph,
            ]
        )
        var cachedAttributes: [Style: [NSAttributedString.Key: Any]] = [:]
        for span in spans where NSMaxRange(span.range) <= attributed.length {
            let resolved = cachedAttributes[span.style]
                ?? attributes(for: span.style, baseFont: baseFont)
            cachedAttributes[span.style] = resolved
            attributed.addAttributes(resolved, range: span.range)
        }
        return attributed
    }

    @MainActor
    private static func attributes(
        for style: Style,
        baseFont: UIFont
    ) -> [NSAttributedString.Key: Any] {
        switch style {
        case .comment:
            return [.foregroundColor: UIColor.secondaryLabel]
        case let .section(accent):
            return [
                .foregroundColor: accent.color,
                .font: UIFont.monospacedSystemFont(ofSize: baseFont.pointSize + 0.5, weight: .bold),
            ]
        case let .key(accent):
            return [
                .foregroundColor: accent.color,
                .font: UIFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .semibold),
            ]
        case let .directive(accent):
            let descriptor = UIFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .medium)
                .fontDescriptor
                .withSymbolicTraits(.traitItalic)
            return [
                .foregroundColor: accent.color,
                .font: descriptor.map { UIFont(descriptor: $0, size: baseFont.pointSize) }
                    ?? UIFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .medium),
            ]
        case .string:
            return [
                .foregroundColor: UIColor { traits in
                    traits.userInterfaceStyle == .dark
                        ? UIColor(red: 0.48, green: 0.86, blue: 0.52, alpha: 1)
                        : UIColor(red: 0.12, green: 0.48, blue: 0.22, alpha: 1)
                },
            ]
        case .number:
            return [.foregroundColor: Accent.orange.color]
        case .keyword:
            return [.foregroundColor: Accent.purple.color]
        case .url:
            return [.foregroundColor: Accent.blue.color]
        }
    }

    private static func appendMatches(
        _ expression: NSRegularExpression,
        style: Style,
        text: String,
        range: NSRange,
        to spans: inout [Span]
    ) {
        for match in expression.matches(in: text, range: range) where match.range.length > 0 {
            spans.append(Span(range: match.range, style: style))
        }
    }

    private static func isComment(_ text: String) -> Bool {
        text.hasPrefix("#") || text.hasPrefix(";") || text.hasPrefix("//")
    }

    private static func accent(for name: String) -> Accent {
        let name = name.lowercased()
        if name.contains("dns") { return .purple }
        if name.contains("policy") || name.contains("proxy")
            || name.contains("server") || name.contains("outbound") {
            return .teal
        }
        if name.contains("rule") || name.contains("filter") || name.contains("route") {
            return .orange
        }
        if name.contains("rewrite") || name.contains("mitm") || name.contains("script") {
            return .pink
        }
        if name.contains("general") || name.contains("setting") { return .blue }
        return .indigo
    }

    private static func topLevelAccent(for name: String) -> Accent? {
        switch name.lowercased().replacingOccurrences(of: "_", with: "-") {
        case "dns", "dns-server", "dns-servers":
            return .purple
        case "proxies", "proxy-groups", "policy", "policies", "outbounds":
            return .teal
        case "rules", "rule-providers", "route", "routing":
            return .orange
        case "rewrite", "mitm", "script":
            return .pink
        case "general", "settings":
            return .blue
        default:
            return nil
        }
    }

    private static func inlineCommentLocation(in line: NSString, startingAt start: Int) -> Int? {
        var quote: unichar?
        var escaped = false
        var index = start
        while index < line.length {
            let character = line.character(at: index)
            if escaped {
                escaped = false
            } else if character == 92 {
                escaped = true
            } else if character == 34 || character == 39 {
                quote = quote == character ? nil : (quote == nil ? character : quote)
            } else if quote == nil {
                let previousIsWhitespace = index == start
                    || isWhitespace(line.character(at: index - 1))
                if previousIsWhitespace, character == 35 || character == 59 {
                    return index
                }
                if previousIsWhitespace,
                   character == 47,
                   index + 1 < line.length,
                   line.character(at: index + 1) == 47 {
                    return index
                }
            }
            index += 1
        }
        return nil
    }

    private static func firstUnquotedSeparator(in text: NSString) -> (location: Int, character: unichar)? {
        var quote: unichar?
        var escaped = false
        for index in 0 ..< text.length {
            let character = text.character(at: index)
            if escaped {
                escaped = false
                continue
            }
            if character == 92 {
                escaped = true
                continue
            }
            if character == 34 || character == 39 {
                quote = quote == character ? nil : (quote == nil ? character : quote)
                continue
            }
            guard quote == nil, character == 61 || character == 58 else { continue }
            if character == 58,
               index + 2 < text.length,
               text.character(at: index + 1) == 47,
               text.character(at: index + 2) == 47 {
                continue
            }
            return (index, character)
        }
        return nil
    }

    private static func trimmedContentRange(in text: NSString) -> NSRange? {
        let first = text.rangeOfCharacter(from: CharacterSet.whitespaces.inverted)
        guard first.location != NSNotFound else { return nil }
        var end = text.length
        while end > first.location,
              isWhitespace(text.character(at: end - 1)) {
            end -= 1
        }
        return NSRange(location: first.location, length: end - first.location)
    }

    private static func isValidKey(_ value: String) -> Bool {
        let key = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        guard !key.isEmpty, key.count <= 80, !key.contains(","), !key.contains("://") else {
            return false
        }
        return key.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0)
                || CharacterSet(charactersIn: "_-. ").contains($0)
        }
    }

    private static func directiveRange(in text: NSString) -> NSRange? {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))
        let end = text.rangeOfCharacter(from: separators).location
        let length = end == NSNotFound ? text.length : end
        guard length > 0 else { return nil }
        let candidate = text.substring(with: NSRange(location: 0, length: length))
        guard candidate.unicodeScalars.first.map(CharacterSet.letters.contains) == true,
              candidate.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0)
                      || CharacterSet(charactersIn: "_-").contains($0)
              }) else {
            return nil
        }
        return NSRange(location: 0, length: length)
    }

    private static func isWhitespace(_ character: unichar) -> Bool {
        UnicodeScalar(character).map(CharacterSet.whitespaces.contains) ?? false
    }
}

enum ConfigurationPreviewFormatter {
    static let summaryLineLimit = 18
    static let maximumSummaryLineLength = 480

    /// Walks only as far as the lines it keeps. Splitting the whole string first
    /// materialised every rule in a generated configuration — tens of thousands
    /// of substrings — on each pass of the export view's body.
    static func summary(from content: String) -> String {
        var lines: [String] = []
        lines.reserveCapacity(summaryLineLimit)
        var index = content.startIndex

        while lines.count < summaryLineLimit, index < content.endIndex {
            let remainder = content[index...]
            let lineEnd = remainder.firstIndex(where: \.isNewline) ?? content.endIndex
            let line = content[index ..< lineEnd]
            lines.append(
                line.count > maximumSummaryLineLength
                    ? String(line.prefix(maximumSummaryLineLength)) + " …"
                    : String(line)
            )
            index = lineEnd < content.endIndex ? content.index(after: lineEnd) : content.endIndex
        }

        return lines.joined(separator: "\n")
    }
}

/// The compact export preview contains at most a few lines. Rendering it with
/// SwiftUI avoids the intermittent blank TextKit surface seen when a disabled,
/// non-scrolling `UITextView` is recycled inside the export page's lazy stack.
struct ConfigurationSummaryView: View {
    let text: String

    @MainActor
    private var highlightedText: AttributedString {
        let baseFont = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: UIFont.monospacedSystemFont(ofSize: 12.5, weight: .regular)
        )
        let highlighted = ConfigurationSyntaxHighlighter.attributedString(
            for: text,
            baseFont: baseFont
        )
        return (try? AttributedString(highlighted, including: \.uiKit)) ?? AttributedString(text)
    }

    var body: some View {
        Group {
            if text.isEmpty {
                Text("没有可预览的配置内容")
                    .foregroundStyle(.secondary)
            } else {
                Text(highlightedText)
            }
        }
        .font(.system(.caption, design: .monospaced))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .clipped()
        .accessibilityIdentifier("configuration-summary")
    }
}

@MainActor
enum ConfigurationTextViewFactory {
    static func make(isScrollEnabled: Bool = true) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = isScrollEnabled
        textView.alwaysBounceVertical = isScrollEnabled
        textView.backgroundColor = .clear
        textView.textColor = .label
        textView.contentInsetAdjustmentBehavior = .never
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 24, right: 16)
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.widthTracksTextView = true
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.layoutManager.allowsNonContiguousLayout = true
        textView.font = baseFont()
        textView.adjustsFontForContentSizeCategory = true
        return textView
    }

    static func render(
        _ text: String,
        spans: [ConfigurationSyntaxHighlighter.Span]? = nil,
        in textView: UITextView
    ) {
        let font = baseFont()
        textView.font = font
        textView.attributedText = ConfigurationSyntaxHighlighter.attributedString(
            for: text,
            spans: spans ?? ConfigurationSyntaxHighlighter.spans(in: text),
            baseFont: font
        )
    }

    private static func baseFont() -> UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(
            for: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        )
    }
}

struct ConfigurationTextView: UIViewRepresentable {
    let text: String
    /// Spans the caller already computed off the main thread. Nil means this
    /// view scans the text itself, which is fine for the short summary.
    var spans: [ConfigurationSyntaxHighlighter.Span]?
    var isScrollEnabled = true

    final class Coordinator {
        var renderedText: String?
        var contentSizeCategory: UIContentSizeCategory?
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = ConfigurationTextViewFactory.make(isScrollEnabled: isScrollEnabled)
        ConfigurationTextViewFactory.render(text, spans: spans, in: textView)
        context.coordinator.renderedText = text
        context.coordinator.contentSizeCategory = textView.traitCollection.preferredContentSizeCategory
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        textView.isScrollEnabled = isScrollEnabled
        textView.alwaysBounceVertical = isScrollEnabled
        let contentSizeCategory = textView.traitCollection.preferredContentSizeCategory
        let textChanged = context.coordinator.renderedText != text
        guard textChanged || context.coordinator.contentSizeCategory != contentSizeCategory else {
            return
        }

        let selection = textView.selectedRange
        let contentOffset = textView.contentOffset
        ConfigurationTextViewFactory.render(text, spans: spans, in: textView)
        context.coordinator.renderedText = text
        context.coordinator.contentSizeCategory = contentSizeCategory

        if textChanged {
            textView.setContentOffset(.zero, animated: false)
        } else {
            textView.selectedRange = selection
            textView.setContentOffset(contentOffset, animated: false)
        }
    }
}
