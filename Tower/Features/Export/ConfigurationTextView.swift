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

/// A fixed gutter that keeps logical line numbers visible while the code moves
/// horizontally, matching the spatial model used by GitHub's source viewer.
/// The editor deliberately does not wrap long configuration directives: one
/// source line must continue to read as one source line.
final class ConfigurationLineNumberView: UIView {
    weak var textView: UITextView?
    private(set) var lineStarts: [Int] = [0]
    private var selectedLineIndex = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refresh(text: String, selectedLocation: Int) {
        let source = text as NSString
        var starts = [0]
        if source.length > 0 {
            for index in 0 ..< source.length where source.character(at: index) == 10 {
                starts.append(index + 1)
            }
        }
        lineStarts = starts
        selectedLineIndex = lineIndex(containing: selectedLocation)
        setNeedsDisplay()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let textView else { return }
        let layoutManager = textView.layoutManager
        let textContainer = textView.textContainer
        layoutManager.ensureLayout(for: textContainer)

        let visibleRect = CGRect(origin: textView.contentOffset, size: textView.bounds.size)
            .offsetBy(
                dx: -textView.textContainerInset.left,
                dy: -textView.textContainerInset.top
            )
        let glyphRange = layoutManager.glyphRange(
            forBoundingRect: visibleRect,
            in: textContainer
        )
        guard glyphRange.location != NSNotFound else { return }

        var drewLine = false
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) {
            [weak self] lineRect, _, _, fragmentGlyphRange, _ in
            guard let self else { return }
            let characterLocation = fragmentGlyphRange.location < layoutManager.numberOfGlyphs
                ? layoutManager.characterIndexForGlyph(at: fragmentGlyphRange.location)
                : max(0, textView.textStorage.length - 1)
            let lineIndex = lineIndex(containing: characterLocation)
            let y = lineRect.minY
                + textView.textContainerInset.top
                - textView.contentOffset.y
            drawLineNumber(lineIndex + 1, selected: lineIndex == selectedLineIndex, y: y)
            drewLine = true
        }

        if !drewLine, lineStarts.count == 1 {
            drawLineNumber(1, selected: true, y: textView.textContainerInset.top)
        }
    }

    private func drawLineNumber(_ number: Int, selected: Bool, y: CGFloat) {
        let font = UIFont.monospacedDigitSystemFont(
            ofSize: 11,
            weight: selected ? .semibold : .regular
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: selected ? (tintColor ?? UIColor.systemBlue) : UIColor.tertiaryLabel,
        ]
        let value = String(number) as NSString
        let size = value.size(withAttributes: attributes)
        value.draw(
            at: CGPoint(x: max(4, bounds.width - size.width - 9), y: y),
            withAttributes: attributes
        )
    }

    private func lineIndex(containing location: Int) -> Int {
        var lower = 0
        var upper = lineStarts.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if lineStarts[middle] <= location {
                lower = middle + 1
            } else {
                upper = middle
            }
        }
        return max(0, lower - 1)
    }
}

final class ConfigurationCodeEditorView: UIView {
    let gutterWidth: CGFloat = 46
    let textView: UITextView
    let lineNumberView = ConfigurationLineNumberView()
    private let separator = UIView()

    override init(frame: CGRect) {
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        // Keep even generated rule-heavy profiles on one logical line without
        // capping the document after only a few thousand rows.
        let textContainer = NSTextContainer(size: CGSize(width: 32_000, height: 1_000_000))
        textContainer.widthTracksTextView = false
        textContainer.lineBreakMode = .byClipping
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        textView = UITextView(frame: .zero, textContainer: textContainer)
        super.init(frame: frame)
        backgroundColor = .systemBackground
        lineNumberView.textView = textView
        separator.backgroundColor = .separator
        addSubview(lineNumberView)
        addSubview(separator)
        addSubview(textView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        lineNumberView.frame = CGRect(x: 0, y: 0, width: gutterWidth, height: bounds.height)
        separator.frame = CGRect(x: gutterWidth, y: 0, width: 1 / traitCollection.displayScale, height: bounds.height)
        textView.frame = CGRect(
            x: gutterWidth + separator.frame.width,
            y: 0,
            width: max(0, bounds.width - gutterWidth - separator.frame.width),
            height: bounds.height
        )
    }
}

@MainActor
enum ConfigurationEditorTextViewFactory {
    static func make() -> ConfigurationCodeEditorView {
        let editor = ConfigurationCodeEditorView()
        let textView = editor.textView
        textView.isEditable = true
        textView.isSelectable = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.alwaysBounceHorizontal = true
        textView.keyboardDismissMode = .interactive
        textView.backgroundColor = .systemBackground
        textView.contentInsetAdjustmentBehavior = .never
        textView.textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 24, right: 18)
        textView.textContainer.lineFragmentPadding = 0
        // UITextView enables width tracking while adopting the container, so
        // restore the code-editor contract after the view has been created.
        textView.textContainer.widthTracksTextView = false
        textView.textContainer.lineBreakMode = .byClipping
        textView.layoutManager.allowsNonContiguousLayout = true
        textView.adjustsFontForContentSizeCategory = true
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.spellCheckingType = .no
        textView.accessibilityLabel = String(localized: "规则配置文本")
        textView.accessibilityIdentifier = "rule-scheme-configuration-editor"
        return editor
    }

    static func render(
        _ text: String,
        spans: [ConfigurationSyntaxHighlighter.Span]? = nil,
        in editor: ConfigurationCodeEditorView
    ) {
        let textView = editor.textView
        let selectedRange = textView.selectedRange
        let contentOffset = textView.contentOffset
        let font = baseFont()
        textView.attributedText = ConfigurationSyntaxHighlighter.attributedString(
            for: text,
            spans: spans ?? ConfigurationSyntaxHighlighter.spans(in: text),
            baseFont: font
        )
        textView.typingAttributes = [
            .font: font,
            .foregroundColor: UIColor.label,
        ]
        textView.selectedRange = NSRange(
            location: min(selectedRange.location, textView.textStorage.length),
            length: min(
                selectedRange.length,
                max(0, textView.textStorage.length - min(selectedRange.location, textView.textStorage.length))
            )
        )
        textView.setContentOffset(contentOffset, animated: false)
        editor.lineNumberView.refresh(
            text: text,
            selectedLocation: textView.selectedRange.location
        )
    }

    private static func baseFont() -> UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(
            for: UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        )
    }
}

struct ConfigurationEditorTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        var isFocused: Binding<Bool>
        weak var editor: ConfigurationCodeEditorView?
        var renderedText: String?
        var contentSizeCategory: UIContentSizeCategory?
        var highlightTask: Task<Void, Never>?
        var isRendering = false

        init(text: Binding<String>, isFocused: Binding<Bool>) {
            self.text = text
            self.isFocused = isFocused
        }

        deinit {
            highlightTask?.cancel()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isFocused.wrappedValue = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isFocused.wrappedValue = false
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isRendering, let editor else { return }
            let snapshot = textView.text ?? ""
            renderedText = snapshot
            text.wrappedValue = snapshot
            editor.lineNumberView.refresh(
                text: snapshot,
                selectedLocation: textView.selectedRange.location
            )
            scheduleHighlight(for: snapshot)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            editor?.lineNumberView.refresh(
                text: textView.text ?? "",
                selectedLocation: textView.selectedRange.location
            )
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            editor?.lineNumberView.setNeedsDisplay()
        }

        private func scheduleHighlight(for snapshot: String) {
            highlightTask?.cancel()
            highlightTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled, let self, let editor else { return }
                let spans = await Task.detached(priority: .userInitiated) {
                    ConfigurationSyntaxHighlighter.spans(in: snapshot)
                }.value
                guard !Task.isCancelled, editor.textView.text == snapshot else { return }
                isRendering = true
                ConfigurationEditorTextViewFactory.render(snapshot, spans: spans, in: editor)
                isRendering = false
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, isFocused: $isFocused)
    }

    func makeUIView(context: Context) -> ConfigurationCodeEditorView {
        let editor = ConfigurationEditorTextViewFactory.make()
        editor.textView.delegate = context.coordinator
        context.coordinator.editor = editor
        ConfigurationEditorTextViewFactory.render(text, in: editor)
        context.coordinator.renderedText = text
        context.coordinator.contentSizeCategory = editor.traitCollection.preferredContentSizeCategory
        return editor
    }

    func updateUIView(_ editor: ConfigurationCodeEditorView, context: Context) {
        let contentSizeCategory = editor.traitCollection.preferredContentSizeCategory
        if context.coordinator.renderedText != text
            || context.coordinator.contentSizeCategory != contentSizeCategory {
            context.coordinator.isRendering = true
            ConfigurationEditorTextViewFactory.render(text, in: editor)
            context.coordinator.renderedText = text
            context.coordinator.contentSizeCategory = contentSizeCategory
            context.coordinator.isRendering = false
        }

        if isFocused, !editor.textView.isFirstResponder {
            editor.textView.becomeFirstResponder()
        } else if !isFocused, editor.textView.isFirstResponder {
            editor.textView.resignFirstResponder()
        }
    }
}
