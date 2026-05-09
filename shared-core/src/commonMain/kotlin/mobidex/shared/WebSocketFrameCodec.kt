package mobidex.shared

class WebSocketFrameCodecException(message: String) : Exception(message)

object WebSocketOpcode {
    const val Continuation: Int = 0x0
    const val Text: Int = 0x1
    const val Binary: Int = 0x2
    const val Close: Int = 0x8
    const val Ping: Int = 0x9
    const val Pong: Int = 0xA
}

data class WebSocketFrame(
    val fin: Boolean,
    val opcode: Int,
    val payload: ByteArray,
)

data class WebSocketFrameParseResult(
    val frame: WebSocketFrame,
    val remaining: ByteArray,
)

object WebSocketFrameCodec {
    @Throws(WebSocketFrameCodecException::class)
    fun parse(buffer: ByteArray): WebSocketFrameParseResult? {
        val parser = WebSocketFrameParser(requireUnmasked = false)
        parser.append(buffer)
        val frame = parser.nextFrame() ?: return null
        return WebSocketFrameParseResult(frame = frame, remaining = parser.remainingBytes())
    }

    @Throws(WebSocketFrameCodecException::class)
    fun parseServerFrame(buffer: ByteArray): WebSocketFrameParseResult? {
        val parser = WebSocketFrameParser(requireUnmasked = true)
        parser.append(buffer)
        val frame = parser.nextFrame() ?: return null
        return WebSocketFrameParseResult(frame = frame, remaining = parser.remainingBytes())
    }

    @Throws(WebSocketFrameCodecException::class)
    fun encodeClientFrame(opcode: Int, payload: ByteArray, mask: ByteArray): ByteArray {
        if (opcode !in supportedOpcodes) {
            throw WebSocketFrameCodecException("Cannot encode unsupported websocket opcode $opcode.")
        }
        if (mask.size != 4) {
            throw WebSocketFrameCodecException("Websocket client frame mask must be exactly 4 bytes.")
        }
        return encode(opcode = opcode, payload = payload, mask = mask)
    }

    fun encodeServerFrame(opcode: Int, payload: ByteArray): ByteArray =
        encode(opcode = opcode, payload = payload, mask = null)

    internal fun ensureSupportedOpcode(opcode: Int) {
        if (opcode !in supportedOpcodes) {
            throw WebSocketFrameCodecException("Received unsupported websocket opcode $opcode.")
        }
    }

    internal fun validateFrameHeader(fin: Boolean, opcode: Int, length: Int, masked: Boolean, requireUnmasked: Boolean) {
        ensureSupportedOpcode(opcode)
        if (requireUnmasked && masked) {
            throw WebSocketFrameCodecException("Received masked websocket frame from server.")
        }
        if (opcode.isControlOpcode) {
            if (!fin) {
                throw WebSocketFrameCodecException("Received fragmented websocket control frame.")
            }
            if (length > 125) {
                throw WebSocketFrameCodecException("Received oversized websocket control frame.")
            }
        }
    }

    private fun encode(opcode: Int, payload: ByteArray, mask: ByteArray?): ByteArray {
        validateFrameHeader(fin = true, opcode = opcode, length = payload.size, masked = mask != null, requireUnmasked = false)
        val headerLength = when {
            payload.size < 126 -> 2
            payload.size <= UShort.MAX_VALUE.toInt() -> 4
            else -> 10
        }
        val maskLength = mask?.size ?: 0
        val output = ByteArray(headerLength + maskLength + payload.size)
        output[0] = (0x80 or opcode).toByte()
        var offset = 2
        val maskBit = if (mask != null) 0x80 else 0
        when {
            payload.size < 126 -> output[1] = (maskBit or payload.size).toByte()
            payload.size <= UShort.MAX_VALUE.toInt() -> {
                output[1] = (maskBit or 126).toByte()
                output[2] = ((payload.size shr 8) and 0xFF).toByte()
                output[3] = (payload.size and 0xFF).toByte()
                offset = 4
            }
            else -> {
                output[1] = (maskBit or 127).toByte()
                val length = payload.size.toLong()
                for (shift in 56 downTo 0 step 8) {
                    output[offset] = ((length shr shift) and 0xFF).toByte()
                    offset += 1
                }
            }
        }
        if (mask != null) {
            mask.copyInto(output, destinationOffset = offset)
            offset += mask.size
            payload.forEachIndexed { index, byte ->
                output[offset + index] = (byte.unsigned xor mask[index % 4].unsigned).toByte()
            }
        } else {
            payload.copyInto(output, destinationOffset = offset)
        }
        return output
    }

    private val supportedOpcodes = setOf(
        WebSocketOpcode.Continuation,
        WebSocketOpcode.Text,
        WebSocketOpcode.Binary,
        WebSocketOpcode.Close,
        WebSocketOpcode.Ping,
        WebSocketOpcode.Pong,
    )
}

class WebSocketFrameParser(
    private val requireUnmasked: Boolean = true,
) {
    private val chunks = mutableListOf<ByteArray>()
    private var firstChunkOffset = 0
    private var available = 0

    fun append(bytes: ByteArray) {
        if (bytes.isEmpty()) return
        chunks += bytes
        available += bytes.size
    }

    @Throws(WebSocketFrameCodecException::class)
    fun nextFrame(): WebSocketFrame? {
        if (available < 2) return null
        val first = byteAt(0)
        if (first and 0x70 != 0) {
            throw WebSocketFrameCodecException("Received websocket frame with reserved bits set.")
        }
        val second = byteAt(1)
        val fin = first and 0x80 != 0
        val opcode = first and 0x0F

        var offset = 2
        var length = second and 0x7F
        if (length == 126) {
            if (available < 4) return null
            length = (byteAt(2) shl 8) or byteAt(3)
            offset = 4
        } else if (length == 127) {
            if (available < 10) return null
            if (byteAt(2) and 0x80 != 0) {
                throw WebSocketFrameCodecException("Websocket frame payload length uses the reserved sign bit.")
            }
            var length64 = 0L
            for (index in 0 until 8) {
                length64 = (length64 shl 8) or byteAt(2 + index).toLong()
            }
            if (length64 > Int.MAX_VALUE) {
                throw WebSocketFrameCodecException("Websocket frame payload is too large.")
            }
            length = length64.toInt()
            offset = 10
        }

        val masked = second and 0x80 != 0
        WebSocketFrameCodec.validateFrameHeader(
            fin = fin,
            opcode = opcode,
            length = length,
            masked = masked,
            requireUnmasked = requireUnmasked,
        )

        val mask = if (masked) {
            if (available < offset + 4) return null
            ByteArray(4) { byteAt(offset + it).toByte() }.also { offset += 4 }
        } else {
            ByteArray(0)
        }
        if (available < offset + length) return null

        val payload = copyRange(offset, length)
        if (masked) {
            for (index in payload.indices) {
                payload[index] = (payload[index].unsigned xor mask[index % 4].unsigned).toByte()
            }
        }
        consume(offset + length)
        return WebSocketFrame(fin = fin, opcode = opcode, payload = payload)
    }

    fun remainingBytes(): ByteArray = copyRange(0, available)

    private fun byteAt(offset: Int): Int {
        var currentOffset = offset + firstChunkOffset
        for (chunk in chunks) {
            if (currentOffset < chunk.size) {
                return chunk[currentOffset].unsigned
            }
            currentOffset -= chunk.size
        }
        throw IndexOutOfBoundsException()
    }

    private fun copyRange(offset: Int, length: Int): ByteArray {
        val result = ByteArray(length)
        var copied = 0
        var sourceOffset = offset + firstChunkOffset
        for (chunk in chunks) {
            if (sourceOffset >= chunk.size) {
                sourceOffset -= chunk.size
                continue
            }
            val count = minOf(length - copied, chunk.size - sourceOffset)
            chunk.copyInto(result, destinationOffset = copied, startIndex = sourceOffset, endIndex = sourceOffset + count)
            copied += count
            sourceOffset = 0
            if (copied == length) break
        }
        return result
    }

    private fun consume(count: Int) {
        var remaining = count
        available -= count
        while (remaining > 0 && chunks.isNotEmpty()) {
            val firstChunk = chunks.first()
            val firstRemaining = firstChunk.size - firstChunkOffset
            if (remaining < firstRemaining) {
                firstChunkOffset += remaining
                return
            }
            remaining -= firstRemaining
            chunks.removeAt(0)
            firstChunkOffset = 0
        }
    }
}

class WebSocketMessageAssembler {
    private var fragmentedOpcode: Int? = null
    private val fragmentedPayloads = mutableListOf<ByteArray>()
    private var fragmentedPayloadLength = 0

    @Throws(WebSocketFrameCodecException::class)
    fun append(frame: WebSocketFrame): ByteArray? =
        when (frame.opcode) {
            WebSocketOpcode.Text, WebSocketOpcode.Binary -> {
                if (fragmentedOpcode != null) {
                    throw WebSocketFrameCodecException("Received websocket data frame before fragmented message completed.")
                }
                if (!frame.fin) {
                    fragmentedOpcode = frame.opcode
                    appendFragment(frame.payload)
                    null
                } else {
                    frame.payload
                }
            }
            WebSocketOpcode.Continuation -> {
                if (fragmentedOpcode == null) {
                    throw WebSocketFrameCodecException("Received websocket continuation without an initial frame.")
                }
                appendFragment(frame.payload)
                if (!frame.fin) {
                    null
                } else {
                    val payload = combinedFragments()
                    fragmentedOpcode = null
                    fragmentedPayloads.clear()
                    fragmentedPayloadLength = 0
                    payload
                }
            }
            WebSocketOpcode.Close, WebSocketOpcode.Ping, WebSocketOpcode.Pong -> null
            else -> throw WebSocketFrameCodecException("Received unsupported websocket opcode ${frame.opcode}.")
        }

    private fun appendFragment(payload: ByteArray) {
        fragmentedPayloads += payload
        fragmentedPayloadLength += payload.size
    }

    private fun combinedFragments(): ByteArray {
        val result = ByteArray(fragmentedPayloadLength)
        var offset = 0
        for (fragment in fragmentedPayloads) {
            fragment.copyInto(result, destinationOffset = offset)
            offset += fragment.size
        }
        return result
    }
}

private val Byte.unsigned: Int
    get() = toInt() and 0xFF

private val Int.isControlOpcode: Boolean
    get() = this >= WebSocketOpcode.Close
