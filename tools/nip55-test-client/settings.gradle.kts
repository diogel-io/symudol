// A standalone Android project, not a Flutter module: the test client must be a separate app with
// its own package and signing key, so Symudol sees it as an ordinary NIP-55 client (#69).
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    // Same versions as Symudol's android/settings.gradle.kts.
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

rootProject.name = "nip55-test-client"
include(":app")
