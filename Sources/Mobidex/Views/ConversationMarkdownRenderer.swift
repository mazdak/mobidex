import MobidexShared
import SwiftUI

struct SharedMarkdownView: View {
    private let document: MobidexShared.MarkdownDocument

    init(markdown: String) {
        document = MobidexShared.MarkdownDocumentParser.shared.parse(markdown: markdown)
    }

    var body: some View {
        SharedMarkdownDocumentView(document: document)
    }
}

struct SharedMarkdownDocumentView: View {
    let document: MobidexShared.MarkdownDocument

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(document.blocks.enumerated()), id: \.offset) { _, block in
                SharedMarkdownBlockView(block: block)
            }
        }
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

private struct SharedMarkdownBlockView: View {
    let block: MobidexShared.MarkdownBlock

    var body: some View {
        switch block {
        case let paragraph as MobidexShared.MarkdownBlockParagraph:
            SharedMarkdownInlineText(inlines: paragraph.inlines)
                .fixedSize(horizontal: false, vertical: true)
        case let heading as MobidexShared.MarkdownBlockHeading:
            SharedMarkdownInlineText(inlines: heading.inlines)
                .font(headingFont(Int(heading.level)))
                .fontWeight(.semibold)
                .fixedSize(horizontal: false, vertical: true)
        case let list as MobidexShared.MarkdownBlockBulletList:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(list.items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("•")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(item.blocks.enumerated()), id: \.offset) { _, child in
                                SharedMarkdownBlockView(block: child)
                            }
                        }
                    }
                }
            }
        case let list as MobidexShared.MarkdownBlockOrderedList:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(list.items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("\(Int(list.start) + index).")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(item.blocks.enumerated()), id: \.offset) { _, child in
                                SharedMarkdownBlockView(block: child)
                            }
                        }
                    }
                }
            }
        case let code as MobidexShared.MarkdownBlockCodeBlock:
            ScrollView(.horizontal, showsIndicators: true) {
                Text(code.code)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        case let quote as MobidexShared.MarkdownBlockQuote:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(quote.blocks.enumerated()), id: \.offset) { _, child in
                    SharedMarkdownBlockView(block: child)
                }
            }
            .padding(.leading, 10)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 3)
            }
        default:
            EmptyView()
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title3
        case 2: .headline
        default: .subheadline
        }
    }
}

private struct SharedMarkdownInlineText: View {
    let inlines: [MobidexShared.MarkdownInline]

    var body: some View {
        Text(attributedText)
    }

    private var attributedText: AttributedString {
        var result = AttributedString()
        append(inlines, into: &result)
        return result
    }

    private func append(_ inlines: [MobidexShared.MarkdownInline], into result: inout AttributedString) {
        for inline in inlines {
            var value: AttributedString
            switch inline {
            case let text as MobidexShared.MarkdownInlineText:
                value = AttributedString(text.text)
            case let code as MobidexShared.MarkdownInlineCode:
                value = AttributedString(code.text)
                value.font = .system(.body, design: .monospaced)
                value.foregroundColor = .primary
            case let emphasis as MobidexShared.MarkdownInlineEmphasis:
                value = attributed(children: emphasis.children)
                value.inlinePresentationIntent = .emphasized
            case let strong as MobidexShared.MarkdownInlineStrong:
                value = attributed(children: strong.children)
                value.inlinePresentationIntent = .stronglyEmphasized
            case let link as MobidexShared.MarkdownInlineLink:
                value = attributed(children: link.children)
                value.foregroundColor = .accentColor
                if let url = url(from: link.destination) {
                    value.link = url
                }
            case _ as MobidexShared.MarkdownInlineLineBreak:
                value = AttributedString("\n")
            default:
                value = AttributedString()
            }
            result += value
        }
    }

    private func attributed(children: [MobidexShared.MarkdownInline]) -> AttributedString {
        var result = AttributedString()
        append(children, into: &result)
        return result
    }

    private func url(from destination: String) -> URL? {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return nil
    }
}
