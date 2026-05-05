plugins {
    kotlin("multiplatform")
    id("com.android.library")
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
