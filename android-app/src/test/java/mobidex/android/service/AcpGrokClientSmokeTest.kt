package mobidex.android.service

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.receiveAsFlow
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import mobidex.shared.CodexSessionItem
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Focused smoke for AcpGrokClient + the shared mapper (toCodexSessionItem / toCodexSessionItems).
 * Uses a minimal mock CodexLineTransport that replays canned ACP JSON-RPC lines.
 * Verifies that Grok/ACP chunks flow out as the *exact* existing CodexSessionItem kinds
 * the UI already renders (Reasoning for thoughts, AgentMessage, ToolCall, Plan, AgentEvent).
 *
 * No real SSH or grok binary required. Exercises the critical "properly translated to right UI elements"
 * path added per explicit user request.
 */
class AcpGrokClientSmokeTest {

    private val cannedAcpLines = listOf(
        // initialize result (ack)
        """{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"0.1"}}""",
        // session/new result with sessionId
        """{"jsonrpc":"2.0","id":2,"result":{"sessionId":"sess-smoke-001"}}""",
        // session/update: thought chunk (should become Reasoning, collapsed)
        """{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"sess-smoke-001","chunk":{"type":"agent_thought_chunk","delta":"Thinking about the best way to implement the feature..."}}}""",
        // session/update: agent message
        """{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"sess-smoke-001","chunk":{"type":"agent_message_chunk","delta":"Here is the plan for the ACP integration."}}}""",
        // session/update: tool call
        """{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"sess-smoke-001","chunk":{"type":"tool_call","id":"tc-1","name":"read_file","args":{"path":"src/App.kt"},"status":"running"}}}""",
        // session/update: plan
        """{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"sess-smoke-001","chunk":{"type":"plan","title":"ACP Sketch","content":"1. Raw transport\n2. Client + mapper\n3. Wiring"}}}""",
        // session/update: approval request (surfaces as AgentEvent)
        """{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"sess-smoke-001","chunk":{"type":"approval_request","id":"ap-42","title":"Run command?","detail":"git status"}}}""",
    )

    @Test
    fun smoke_acpClientWithMockTransport_emitsMappedCodexSessionItems() = runBlocking {
        val mockTransport = CannedLinesTransport(cannedAcpLines)
        val client = AcpGrokClient(mockTransport)

        // Drive only the parts that don't require exact response ID matching for this smoke.
        // The inbound canned notifications (with session/update chunks) will still be classified + mapped.
        client.initialize()

        // Collect the mapped items that the UI will receive (the core value of the chunk)
        val collected = mutableListOf<CodexSessionItem>()
        withTimeout(1_500) {
            var seenThought = false
            var seenMessage = false
            var seenTool = false
            var seenPlan = false
            var seenApproval = false

            try {
                client.sessionItems.collect { item ->
                    collected += item
                    when (item) {
                        is CodexSessionItem.Reasoning -> seenThought = true
                        is CodexSessionItem.AgentMessage -> seenMessage = true
                        is CodexSessionItem.ToolCall -> seenTool = true
                        is CodexSessionItem.Plan -> seenPlan = true
                        is CodexSessionItem.AgentEvent -> if (item.label.contains("approval", ignoreCase = true)) seenApproval = true
                        else -> {}
                    }
                    if (seenThought && seenMessage && seenTool && seenPlan && seenApproval) {
                        throw CancellationException("enough items for smoke")
                    }
                }
            } catch (_: CancellationException) {
                // expected drain
            }
        }

        client.close()

        // Core assertions — these prove the mapper + client path works end-to-end for the UI
        assertTrue("Should have received at least one Reasoning (from thought_chunk)", collected.any { it is CodexSessionItem.Reasoning })
        assertTrue("Should have received an AgentMessage", collected.any { it is CodexSessionItem.AgentMessage })
        assertTrue("Should have received a ToolCall", collected.any { it is CodexSessionItem.ToolCall })
        assertTrue("Should have received a Plan", collected.any { it is CodexSessionItem.Plan })
        assertTrue("Should have received an AgentEvent for approval", collected.any { it is CodexSessionItem.AgentEvent && it.label.contains("approval", ignoreCase = true) })

        // Bonus: the thought content made it through
        val reasoning = collected.filterIsInstance<CodexSessionItem.Reasoning>().firstOrNull()
        assertTrue("Reasoning should contain the thought delta", reasoning?.content?.any { it.contains("Thinking about the best way") } == true)
    }

    private class CannedLinesTransport(private val lines: List<String>) : CodexLineTransport {
        private val ch = Channel<String>(Channel.UNLIMITED)

        override val inboundLines: Flow<String> = ch.receiveAsFlow()

        init {
            // Pump all canned lines immediately so the client's readLoop sees the session/update
            // notifications (and mapper) regardless of sendLine timing or ID correlation in the smoke.
            lines.forEach { ch.trySend(it) }
            ch.close()
        }

        override suspend fun sendLine(line: String) {
            // No-op for this canned replay smoke; inbound data is pre-pumped.
        }

        override suspend fun close() {
            ch.close()
        }
    }
}
