plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "io.diogel.nip55testclient"
    compileSdk = 36
    // The one build-tools version in ghcr.io/cirruslabs/flutter:3.44.0, so CI downloads none.
    buildToolsVersion = "36.0.0"

    defaultConfig {
        applicationId = "io.diogel.nip55testclient"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    // A fixed, test-only key (keystore/README.md): grants are matched on package and signing
    // certificate, so the client's certificate must be stable across machines and CI.
    signingConfigs {
        create("testClient") {
            storeFile = file("../keystore/test-client.jks")
            storePassword = "nip55-test-client"
            keyAlias = "test-client"
            keyPassword = "nip55-test-client"
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("testClient")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    testOptions {
        unitTests {
            isReturnDefaultValues = true
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    // org.json is a stub in android.jar; the real library lets the JVM tests parse events.
    testImplementation("org.json:json:20231013")
}
