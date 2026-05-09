package mobidex.shared

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class WebSocketFrameCodecTest {
    @Test
    fun encodedClientTextFrameIsMaskedAndRoundTripsThroughParser() {
        val payload = """{"jsonrpc":"2.0"}""".encodeToByteArray()
        val encoded = WebSocketFrameCodec.encodeClientFrame(
            opcode = WebSocketOpcode.Text,
            payload = payload,
            mask = byteArrayOf(1, 2, 3, 4),
        )

        assertTrue(encoded[1].toInt() and 0x80 != 0)
        val result = assertNotNull(WebSocketFrameCodec.parse(encoded))
        assertEquals(WebSocketOpcode.Text, result.frame.opcode)
        assertTrue(result.frame.fin)
        assertContentEquals(payload, result.frame.payload)
        assertContentEquals(ByteArray(0), result.remaining)
    }

    @Test
    fun parserAcceptsUnmaskedServerTextFrameWithTrailingBytes() {
        val frame = byteArrayOf(0x81.toByte(), 0x02, 'o'.code.toByte(), 'k'.code.toByte(), 0x7F)
        val result = assertNotNull(WebSocketFrameCodec.parse(frame))

        assertEquals(WebSocketOpcode.Text, result.frame.opcode)
        assertEquals("ok", result.frame.payload.decodeToString())
        assertContentEquals(byteArrayOf(0x7F), result.remaining)
    }

    @Test
    fun parserWaitsForCompleteFrame() {
        val partial = byteArrayOf(0x81.toByte(), 0x05, 'h'.code.toByte())

        assertNull(WebSocketFrameCodec.parse(partial))
    }

    @Test
    fun parserHandlesExtendedPayloadLength() {
        val payload = ByteArray(130) { index -> index.toByte() }
        val frame = byteArrayOf(0x82.toByte(), 126, 0, payload.size.toByte()) + payload
        val result = assertNotNull(WebSocketFrameCodec.parse(frame))

        assertEquals(WebSocketOpcode.Binary, result.frame.opcode)
        assertContentEquals(payload, result.frame.payload)
    }

    @Test
    fun parserRejectsReserved64BitPayloadLengthSignBit() {
        val frame = byteArrayOf(0x82.toByte(), 127, 0x80.toByte(), 0, 0, 0, 0, 0, 0, 0)

        assertFailsWith<WebSocketFrameCodecException> {
            WebSocketFrameCodec.parse(frame)
        }
    }

    @Test
    fun serverParserRejectsMaskedAndInvalidControlFrames() {
        assertFailsWith<WebSocketFrameCodecException> {
            WebSocketFrameCodec.parseServerFrame(
                byteArrayOf(0x81.toByte(), 0x80.toByte(), 1, 2, 3, 4)
            )
        }
        assertFailsWith<WebSocketFrameCodecException> {
            WebSocketFrameCodec.parseServerFrame(byteArrayOf(0x19, 0))
        }
        assertFailsWith<WebSocketFrameCodecException> {
            WebSocketFrameCodec.parseServerFrame(byteArrayOf(0x09, 0))
        }
        assertFailsWith<WebSocketFrameCodecException> {
            WebSocketFrameCodec.parseServerFrame(byteArrayOf(0x89.toByte(), 126, 0, 126) + ByteArray(126))
        }
    }

    @Test
    fun statefulServerParserKeepsPartialFrameWithoutReturningRemainderCopies() {
        val parser = WebSocketFrameParser(requireUnmasked = true)

        parser.append(byteArrayOf(0x81.toByte(), 0x02, 'o'.code.toByte()))
        assertNull(parser.nextFrame())
        parser.append(byteArrayOf('k'.code.toByte(), 0x7F))
        val result = assertNotNull(parser.nextFrame())

        assertEquals("ok", result.payload.decodeToString())
        assertContentEquals(byteArrayOf(0x7F), parser.remainingBytes())
    }

    @Test
    fun assemblerCombinesFragmentedMessages() {
        val assembler = WebSocketMessageAssembler()

        assertNull(assembler.append(WebSocketFrame(fin = false, opcode = WebSocketOpcode.Text, payload = "hel".encodeToByteArray())))
        val message = assembler.append(WebSocketFrame(fin = true, opcode = WebSocketOpcode.Continuation, payload = "lo".encodeToByteArray()))

        assertEquals("hello", message?.decodeToString())
    }

    @Test
    fun assemblerRejectsDataFrameBeforeFragmentedMessageCompletes() {
        val assembler = WebSocketMessageAssembler()

        assertNull(assembler.append(WebSocketFrame(fin = false, opcode = WebSocketOpcode.Text, payload = "hel".encodeToByteArray())))
        assertFailsWith<WebSocketFrameCodecException> {
            assembler.append(WebSocketFrame(fin = true, opcode = WebSocketOpcode.Text, payload = "lo".encodeToByteArray()))
        }
    }

    @Test
    fun assemblerRejectsContinuationWithoutInitialFrame() {
        val assembler = WebSocketMessageAssembler()

        assertFailsWith<WebSocketFrameCodecException> {
            assembler.append(WebSocketFrame(fin = true, opcode = WebSocketOpcode.Continuation, payload = ByteArray(0)))
        }
    }
}
