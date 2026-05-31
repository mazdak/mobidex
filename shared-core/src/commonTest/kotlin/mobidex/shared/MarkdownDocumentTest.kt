package mobidex.shared

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue

class MarkdownDocumentTest {
    @Test
    fun parsesEmphasisListsLinksAndCodeBlocks() {
        val document = MarkdownDocumentParser.parse(
            """
            Hello **bold** and *emph* with [a link](https://example.com).

            - first
            - `second`

            ```kotlin
            println("ok")
            ```
            """.trimIndent()
        )

        val paragraph = assertIs<MarkdownBlock.Paragraph>(document.blocks[0])
        assertTrue(paragraph.inlines.any { it is MarkdownInline.Strong })
        assertTrue(paragraph.inlines.any { it is MarkdownInline.Emphasis })
        assertTrue(paragraph.inlines.any { it is MarkdownInline.Link })

        val list = assertIs<MarkdownBlock.BulletList>(document.blocks[1])
        assertEquals(2, list.items.size)
        assertIs<MarkdownInline.Code>(
            assertIs<MarkdownBlock.Paragraph>(list.items[1].blocks.single()).inlines.single()
        )

        val code = assertIs<MarkdownBlock.CodeBlock>(document.blocks[2])
        assertEquals("kotlin", code.language)
        assertEquals("println(\"ok\")", code.code)
    }

    @Test
    fun stripsCodexDirectivesOutsideCodeFences() {
        val document = MarkdownDocumentParser.parse(
            """
            Keep this.

            ```text
            ::git-stage{cwd="/tmp/visible"}
            ```

            ::git-stage{cwd="/tmp/hidden"}
            """.trimIndent()
        )

        assertEquals(2, document.blocks.size)
        assertEquals("Keep this.", assertIs<MarkdownInline.Text>(assertIs<MarkdownBlock.Paragraph>(document.blocks[0]).inlines.single()).text)
        assertTrue(assertIs<MarkdownBlock.CodeBlock>(document.blocks[1]).code.contains("visible"))
    }

    @Test
    fun preservesLiteralDelimiterCharactersAndIncompleteMarkdown() {
        val document = MarkdownDocumentParser.parse("call foo(bar), array[0], and literal ** not closed")
        val paragraph = assertIs<MarkdownBlock.Paragraph>(document.blocks.single())

        assertEquals(
            "call foo(bar), array[0], and literal ** not closed",
            paragraph.inlines.joinToString("") { inline ->
                when (inline) {
                    is MarkdownInline.Text -> inline.text
                    is MarkdownInline.Code -> inline.text
                    MarkdownInline.LineBreak -> "\n"
                    is MarkdownInline.Emphasis -> ""
                    is MarkdownInline.Strong -> ""
                    is MarkdownInline.Link -> ""
                }
            },
        )
    }
}
