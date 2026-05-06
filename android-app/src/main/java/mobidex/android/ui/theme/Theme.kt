package mobidex.android.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val MobidexLightColors = lightColorScheme(
    primary = Color(0xFF2457D6),
    secondary = Color(0xFF556170),
    tertiary = Color(0xFF007C78),
    error = Color(0xFFB3261E),
    surface = Color(0xFFFCFCFF),
    surfaceVariant = Color(0xFFE8ECF4),
    background = Color(0xFFF8F9FD),
)

@Composable
fun MobidexTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = MobidexLightColors,
        content = content,
    )
}
