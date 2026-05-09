package mobidex.android.service

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import mobidex.shared.WebSocketFrameCodec
import mobidex.shared.WebSocketOpcode

class WebSocketFrameCodecTest {
    @Test
    fun encodedClientTextFrameIsMaskedAndRoundTripsThroughParser() {
        val payload = """{"jsonrpc":"2.0"}""".toByteArray(Charsets.UTF_8)
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
        assertEquals("ok", String(result.frame.payload, Charsets.UTF_8))
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
}
