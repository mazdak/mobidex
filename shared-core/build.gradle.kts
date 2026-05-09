plugins {
    kotlin("multiplatform")
    id("com.android.library")
    id("org.jetbrains.kotlin.plugin.serialization")
}

import org.jetbrains.kotlin.gradle.plugin.mpp.apple.XCFramework

kotlin {
    val mobidexShared = XCFramework("MobidexShared")

    jvm()
    androidTarget()
    iosArm64 {
        binaries.framework {
            baseName = "MobidexShared"
            isStatic = true
            mobidexShared.add(this)
        }
    }
    iosSimulatorArm64 {
        binaries.framework {
            baseName = "MobidexShared"
            isStatic = true
            mobidexShared.add(this)
        }
    }
    iosX64 {
        binaries.framework {
            baseName = "MobidexShared"
            isStatic = true
            mobidexShared.add(this)
        }
    }

    sourceSets {
        commonMain.dependencies {
            implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.8.1")
        }

        commonTest.dependencies {
            implementation(kotlin("test"))
        }
    }
}

android {
    namespace = "mobidex.shared"
    compileSdk = 36

    defaultConfig {
        minSdk = 26
    }
}
