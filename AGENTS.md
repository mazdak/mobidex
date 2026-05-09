# Mobidex Agent Notes

- For Android builds, first check for a repo Gradle wrapper, then a PATH `gradle`, then Android Studio-managed/local Gradle availability. On this machine, a usable Gradle exists at `build/gradle-8.13/bin/gradle`; Android Studio's bundled JBR is at `/Applications/Android Studio.app/Contents/jbr/Contents/Home`.
- If a full Gradle build cannot run from the shell, Android resource-only validation can still use the installed Android SDK tools such as `aapt2`, `d8`, `zipalign`, `apksigner`, and `adb`.
- When fixing a product behavior in one client, check whether the same state/model issue exists in the other native client and fix both when it makes sense.
