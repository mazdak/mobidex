package mobidex.android.service

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class OpenAITranscriptionServiceTest {
    @Test
    fun multipartUsesGpt4oTranscribeAndTextResponseFormat() {
        val boundary = "test-boundary"
        val prefix = OpenAITranscriptionMultipart.prefix(boundary).toString(Charsets.UTF_8)
        val suffix = OpenAITranscriptionMultipart.suffix(boundary).toString(Charsets.UTF_8)

        assertEquals("gpt-4o-transcribe", OpenAITranscriptionMultipart.MODEL)
        assertTrue(prefix.contains("Content-Disposition: form-data; name=\"model\""))
        assertTrue(prefix.contains("\r\n\r\ngpt-4o-transcribe\r\n"))
        assertTrue(prefix.contains("Content-Disposition: form-data; name=\"response_format\""))
        assertTrue(prefix.contains("\r\n\r\ntext\r\n"))
        assertTrue(prefix.contains("Content-Disposition: form-data; name=\"file\"; filename=\"recording.m4a\""))
        assertTrue(prefix.contains("Content-Type: audio/mp4"))
        assertEquals("\r\n--$boundary--\r\n", suffix)
    }
}
