package mobidex.shared

import org.intellij.markdown.IElementType
import org.intellij.markdown.MarkdownElementTypes
import org.intellij.markdown.MarkdownTokenTypes
import org.intellij.markdown.ast.ASTNode
import org.intellij.markdown.flavours.commonmark.CommonMarkFlavourDescriptor
import org.intellij.markdown.parser.MarkdownParser

data class MarkdownDocument(
    val blocks: List<MarkdownBlock>,
)

sealed interface MarkdownBlock {
    val kind: String

    data class Paragraph(val inlines: List<MarkdownInline>) : MarkdownBlock {
        override val kind: String = "paragraph"
    }

    data class Heading(val level: Int, val inlines: List<MarkdownInline>) : MarkdownBlock {
        override val kind: String = "heading"
    }

    data class BulletList(val items: List<MarkdownListItem>) : MarkdownBlock {
        override val kind: String = "bulletList"
    }

    data class OrderedList(val start: Int, val items: List<MarkdownListItem>) : MarkdownBlock {
        override val kind: String = "orderedList"
    }

    data class CodeBlock(val code: String, val language: String? = null) : MarkdownBlock {
        override val kind: String = "codeBlock"
    }

    data class Quote(val blocks: List<MarkdownBlock>) : MarkdownBlock {
        override val kind: String = "quote"
    }
}

data class MarkdownListItem(
    val blocks: List<MarkdownBlock>,
)

sealed interface MarkdownInline {
    val kind: String

    data class Text(val text: String) : MarkdownInline {
        override val kind: String = "text"
    }

    data class Emphasis(val children: List<MarkdownInline>) : MarkdownInline {
        override val kind: String = "emphasis"
    }

    data class Strong(val children: List<MarkdownInline>) : MarkdownInline {
        override val kind: String = "strong"
    }

    data class Code(val text: String) : MarkdownInline {
        override val kind: String = "code"
    }

    data class Link(val children: List<MarkdownInline>, val destination: String) : MarkdownInline {
        override val kind: String = "link"
    }

    data object LineBreak : MarkdownInline {
        override val kind: String = "lineBreak"
    }
}

object MarkdownDocumentParser {
    private val flavour = CommonMarkFlavourDescriptor()

    fun parse(markdown: String): MarkdownDocument {
        val displayBody = stripCodexAppDirectives(markdown).trim()
        if (displayBody.isEmpty()) return MarkdownDocument(emptyList())
        val tree = MarkdownParser(flavour).buildMarkdownTreeFromString(displayBody)
        return MarkdownDocument(blocks = tree.children.mapNotNull { block(it, displayBody) })
    }

    private fun block(node: ASTNode, source: String): MarkdownBlock? =
        when (node.type) {
            MarkdownElementTypes.PARAGRAPH -> MarkdownBlock.Paragraph(inlines(node.children, source).normalized())
            MarkdownElementTypes.ATX_1,
            MarkdownElementTypes.SETEXT_1 -> MarkdownBlock.Heading(level = 1, inlines = headingInlines(node, source))
            MarkdownElementTypes.ATX_2,
            MarkdownElementTypes.SETEXT_2 -> MarkdownBlock.Heading(level = 2, inlines = headingInlines(node, source))
            MarkdownElementTypes.ATX_3 -> MarkdownBlock.Heading(level = 3, inlines = headingInlines(node, source))
            MarkdownElementTypes.ATX_4 -> MarkdownBlock.Heading(level = 4, inlines = headingInlines(node, source))
            MarkdownElementTypes.ATX_5 -> MarkdownBlock.Heading(level = 5, inlines = headingInlines(node, source))
            MarkdownElementTypes.ATX_6 -> MarkdownBlock.Heading(level = 6, inlines = headingInlines(node, source))
            MarkdownElementTypes.UNORDERED_LIST -> MarkdownBlock.BulletList(listItems(node, source))
            MarkdownElementTypes.ORDERED_LIST -> MarkdownBlock.OrderedList(orderedListStart(node, source), listItems(node, source))
            MarkdownElementTypes.CODE_FENCE -> MarkdownBlock.CodeBlock(
                code = node.children.filter { it.type == MarkdownTokenTypes.CODE_FENCE_CONTENT }
                    .joinToString("") { it.slice(source) }
                    .trimEnd('\n'),
                language = node.children.firstOrNull { it.type == MarkdownTokenTypes.FENCE_LANG }
                    ?.slice(source)
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() },
            )
            MarkdownElementTypes.CODE_BLOCK -> MarkdownBlock.CodeBlock(
                code = node.children.filter { it.type == MarkdownTokenTypes.CODE_LINE }
                    .joinToString("") { it.slice(source).trimStart() }
                    .trimEnd('\n'),
            )
            MarkdownElementTypes.BLOCK_QUOTE -> MarkdownBlock.Quote(
                blocks = node.children.filter { it.type != MarkdownTokenTypes.BLOCK_QUOTE }
                    .mapNotNull { block(it, source) },
            )
            else -> {
                val children = node.children.mapNotNull { block(it, source) }
                children.singleOrNull() ?: if (children.isNotEmpty()) MarkdownBlock.Quote(children) else null
            }
        }

    private fun headingInlines(node: ASTNode, source: String): List<MarkdownInline> {
        val content = node.children.filter {
            it.type == MarkdownTokenTypes.ATX_CONTENT || it.type == MarkdownTokenTypes.SETEXT_CONTENT
        }
        return inlines(if (content.isEmpty()) node.children else content, source).normalized()
    }

    private fun listItems(node: ASTNode, source: String): List<MarkdownListItem> =
        node.children.filter { it.type == MarkdownElementTypes.LIST_ITEM }.map { item ->
            val blocks = item.children
                .filterNot { it.type == MarkdownTokenTypes.LIST_BULLET || it.type == MarkdownTokenTypes.LIST_NUMBER }
                .mapNotNull { block(it, source) }
            MarkdownListItem(blocks.ifEmpty {
                listOf(MarkdownBlock.Paragraph(inlines(item.children, source).normalized()))
            })
        }

    private fun orderedListStart(node: ASTNode, source: String): Int =
        node.children.firstOrNull { it.type == MarkdownElementTypes.LIST_ITEM }
            ?.children
            ?.firstOrNull { it.type == MarkdownTokenTypes.LIST_NUMBER }
            ?.slice(source)
            ?.takeWhile { it.isDigit() }
            ?.toIntOrNull()
            ?: 1

    private fun inlines(nodes: List<ASTNode>, source: String): List<MarkdownInline> =
        nodes.flatMap { inline(it, source) }

    private fun inline(node: ASTNode, source: String): List<MarkdownInline> =
        when (node.type) {
            MarkdownElementTypes.STRONG -> listOf(MarkdownInline.Strong(inlines(node.contentChildren(), source).normalized()))
            MarkdownElementTypes.EMPH -> listOf(MarkdownInline.Emphasis(inlines(node.contentChildren(), source).normalized()))
            MarkdownElementTypes.CODE_SPAN -> listOf(MarkdownInline.Code(codeSpanText(node, source)))
            MarkdownElementTypes.INLINE_LINK -> listOf(inlineLink(node, source))
            MarkdownElementTypes.AUTOLINK -> listOf(MarkdownInline.Link(
                children = listOf(MarkdownInline.Text(node.slice(source).trim('<', '>'))),
                destination = node.slice(source).trim('<', '>'),
            ))
            MarkdownTokenTypes.TEXT,
            MarkdownTokenTypes.WHITE_SPACE,
            MarkdownTokenTypes.ATX_CONTENT,
            MarkdownTokenTypes.SETEXT_CONTENT -> listOf(MarkdownInline.Text(node.slice(source)))
            MarkdownTokenTypes.EOL,
            MarkdownTokenTypes.HARD_LINE_BREAK -> listOf(MarkdownInline.LineBreak)
            else -> if (node.children.isEmpty()) {
                listOf(MarkdownInline.Text(node.slice(source)))
            } else {
                inlines(node.children, source)
            }
        }

    private fun inlineLink(node: ASTNode, source: String): MarkdownInline.Link {
        val textNode = node.children.firstOrNull { it.type == MarkdownElementTypes.LINK_TEXT }
        val destination = node.children.firstOrNull { it.type == MarkdownElementTypes.LINK_DESTINATION }
            ?.slice(source)
            ?.trim()
            .orEmpty()
        val label = textNode?.let { inlines(it.contentChildren(), source).normalized() }
            ?: listOf(MarkdownInline.Text(destination))
        return MarkdownInline.Link(label, destination)
    }

    private fun codeSpanText(node: ASTNode, source: String): String =
        node.children
            .filter { it.type != MarkdownTokenTypes.BACKTICK && it.type != MarkdownTokenTypes.ESCAPED_BACKTICKS }
            .joinToString("") { it.slice(source) }
            .ifEmpty { node.slice(source).trim('`') }

    private fun ASTNode.contentChildren(): List<ASTNode> =
        children.filterNot {
            it.type == MarkdownTokenTypes.EMPH ||
                it.type == MarkdownTokenTypes.BACKTICK ||
                it.type == MarkdownTokenTypes.LBRACKET ||
                it.type == MarkdownTokenTypes.RBRACKET ||
                it.type == MarkdownTokenTypes.LPAREN ||
                it.type == MarkdownTokenTypes.RPAREN
        }

    private fun ASTNode.slice(source: String): String =
        source.substring(startOffset.coerceAtLeast(0), endOffset.coerceAtMost(source.length))

    private fun List<MarkdownInline>.normalized(): List<MarkdownInline> {
        val result = mutableListOf<MarkdownInline>()
        for (inline in this) {
            if (inline is MarkdownInline.Text && inline.text.isEmpty()) continue
            val last = result.lastOrNull()
            if (last is MarkdownInline.Text && inline is MarkdownInline.Text) {
                result[result.lastIndex] = MarkdownInline.Text(last.text + inline.text)
            } else {
                result += inline
            }
        }
        return result
    }

    private fun stripCodexAppDirectives(body: String): String {
        var isInFence = false
        return body.lines().filter { line ->
            val trimmed = line.trim()
            if (trimmed.startsWith("```") || trimmed.startsWith("~~~")) {
                isInFence = !isInFence
                true
            } else {
                isInFence || !isCodexAppDirectiveLine(trimmed)
            }
        }.joinToString("\n")
    }

    private fun isCodexAppDirectiveLine(line: String): Boolean {
        var remaining = line
        var foundDirective = false
        val names = listOf("archive", "code-comment", "git-commit", "git-create-branch", "git-create-pr", "git-push", "git-stage")
        while (remaining.isNotEmpty()) {
            remaining = remaining.trimStart()
            if (remaining.isEmpty()) return foundDirective
            val name = names.firstOrNull { remaining.startsWith("::$it") } ?: return false
            remaining = remaining.drop(2 + name.length)
            if (!remaining.startsWith("{")) return false
            val closeBrace = remaining.indexOf('}')
            if (closeBrace < 0) return false
            remaining = remaining.drop(closeBrace + 1)
            foundDirective = true
        }
        return foundDirective
    }
}
