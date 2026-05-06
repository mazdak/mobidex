package mobidex.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import mobidex.android.ui.MobidexApp
import mobidex.android.ui.theme.MobidexTheme

class MainActivity : ComponentActivity() {
    private val model: AppViewModel by viewModels {
        AppViewModel.Factory(applicationContext)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MobidexTheme {
                MobidexApp(model = model)
            }
        }
    }
}
