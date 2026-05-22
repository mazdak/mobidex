package mobidex.android.service

import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class OpenAITranscriptionService {
    suspend fun transcribe(audioFile: File, apiKey: String): String = withContext(Dispatchers.IO) {
        val boundary = "mobidex-${UUID.randomUUID()}"
        val connection = (URL("https://api.openai.com/v1/audio/transcriptions").openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            connectTimeout = 20_000
            readTimeout = 60_000
            setRequestProperty("Authorization", "Bearer $apiKey")
            setRequestProperty("Content-Type", "multipart/form-data; boundary=$boundary")
        }
        connection.outputStream.use { output ->
            output.write(OpenAITranscriptionMultipart.prefix(boundary))
            audioFile.inputStream().use { it.copyTo(output) }
            output.write(OpenAITranscriptionMultipart.suffix(boundary))
        }
        val status = connection.responseCode
        val stream = if (status in 200..299) connection.inputStream else connection.errorStream
        val body = stream?.bufferedReader()?.use { it.readText() }.orEmpty().trim()
        if (status !in 200..299) {
            error("OpenAI transcription failed ($status): ${body.ifBlank { "Unknown error" }}")
        }
        body.ifBlank { error("OpenAI returned an empty transcription.") }
    }
}

object OpenAITranscriptionMultipart {
    const val MODEL = "gpt-4o-transcribe"

    fun prefix(boundary: String): ByteArray = buildString {
        append("--$boundary\r\n")
        append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        append("$MODEL\r\n")
        append("--$boundary\r\n")
        append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n")
        append("text\r\n")
        append("--$boundary\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"recording.m4a\"\r\n")
        append("Content-Type: audio/mp4\r\n\r\n")
    }.toByteArray(Charsets.UTF_8)

    fun suffix(boundary: String): ByteArray = "\r\n--$boundary--\r\n".toByteArray(Charsets.UTF_8)
}
