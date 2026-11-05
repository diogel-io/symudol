import java.util.Properties

plugins {
    id("com.android.application")
    // No Kotlin plugin here, as in Flutter 3.44's app template: while android.builtInKotlin is
    // false, the Flutter Gradle Plugin applies it, from the version in settings.gradle.kts (#150).
    // The Flutter Gradle Plugin must be applied after the Android Gradle plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

// The upload key signs release builds for Google Play (#37). It is read from android/key.properties
// (gitignored; see key.properties.example) or from SYMUDOL_UPLOAD_* environment variables, which
// override the file, so the passwords need not be written to disk. Nothing here is committed.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

fun uploadSetting(property: String, variable: String): String? =
    // Blank values are ignored per source, so an empty variable falls back to the file.
    System.getenv(variable)?.takeIf { it.isNotBlank() }
        ?: keyProperties.getProperty(property)?.takeIf { it.isNotBlank() }

val uploadStoreFile = uploadSetting("storeFile", "SYMUDOL_UPLOAD_STORE_FILE")
val uploadStorePassword = uploadSetting("storePassword", "SYMUDOL_UPLOAD_STORE_PASSWORD")
val uploadKeyAlias = uploadSetting("keyAlias", "SYMUDOL_UPLOAD_KEY_ALIAS")
val uploadKeyPassword = uploadSetting("keyPassword", "SYMUDOL_UPLOAD_KEY_PASSWORD")
val uploadSettings = mapOf(
    "storeFile" to uploadStoreFile,
    "storePassword" to uploadStorePassword,
    "keyAlias" to uploadKeyAlias,
    "keyPassword" to uploadKeyPassword,
)
val hasUploadKey = uploadSettings.values.all { it != null }
val missingUploadSettings = uploadSettings.filterValues { it == null }.keys
// Half a configuration is a mistake, not "no key". Checked only when a release task runs (below),
// so debug builds, unit tests and Gradle Sync still work.
val uploadKeyPartlyConfigured = !hasUploadKey && missingUploadSettings.size < uploadSettings.size

android {
    namespace = "io.diogel.symudol"
    // Pinned rather than taken from the Flutter plugin, so a Flutter upgrade cannot change them
    // without a reviewed diff (#37).
    // 36: the API the app is compiled against; matches targetSdk.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.diogel.symudol"
        // 24: the floor set by url_launcher_android and image_picker_android.
        minSdk = 24
        // 36: Google Play's target API level requirement for new apps in 2026.
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildFeatures {
        buildConfig = true
    }

    signingConfigs {
        if (hasUploadKey) {
            create("upload") {
                storeFile = file(uploadStoreFile!!)
                storePassword = uploadStorePassword
                keyAlias = uploadKeyAlias
                keyPassword = uploadKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // Without the upload key, release APKs (`flutter run --release`, the emulator and
            // device checks) fall back to the debug key; the guard below stops a Play bundle
            // from ever being debug-signed.
            signingConfig = signingConfigs.getByName(if (hasUploadKey) "upload" else "debug")
            // R8 strips Log.v/d/i from release builds (#14); set here, not left to the
            // Flutter plugin's default, so the rules always apply.
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    testOptions {
        unitTests {
            isReturnDefaultValues = true
            // Robolectric runs the NIP-55 activities and ContentProvider on the JVM (#68); the
            // bridge reads R.string resources, so they must be on the test classpath.
            isIncludeAndroidResources = true
        }
    }
}

kotlin {
    jvmToolchain(17)
}

// AGP 9 packages the merged assets for unit tests (isIncludeAndroidResources, above), and the
// Flutter plugin copies its assets into the same directory without declaring it, which Gradle 9
// rejects (#148). Run the copy first, for each variant that has one.
tasks.configureEach {
    val variant = Regex("package(\\w+)UnitTestForUnitTest").matchEntire(name)?.groupValues?.get(1)
        ?: return@configureEach
    dependsOn(tasks.matching { it.name == "copyFlutterAssets$variant" })
}

val missingUploadKeyMessage =
    "No upload key: create android/key.properties (see android/key.properties.example) or set " +
        "SYMUDOL_UPLOAD_STORE_FILE, SYMUDOL_UPLOAD_STORE_PASSWORD, SYMUDOL_UPLOAD_KEY_ALIAS and " +
        "SYMUDOL_UPLOAD_KEY_PASSWORD."

gradle.taskGraph.whenReady {
    if (hasUploadKey) return@whenReady
    val releaseTasks = allTasks.filter { it.project == project && it.name.contains("Release") }
    if (releaseTasks.isEmpty()) return@whenReady
    if (uploadKeyPartlyConfigured) {
        throw GradleException(
            "The upload key is only partly configured; missing: ${missingUploadSettings.joinToString()}.",
        )
    }
    // signReleaseBundle too, so signing a bundle directly cannot bypass the guard.
    if (releaseTasks.any { it.name == "bundleRelease" || it.name == "signReleaseBundle" }) {
        throw GradleException("$missingUploadKeyMessage A Play bundle is never debug-signed.")
    }
    if (releaseTasks.any { it.name == "assembleRelease" }) {
        // Error level so `flutter build apk`, which hides Gradle warnings, still shows it.
        logger.error("WARNING: $missingUploadKeyMessage This release APK is signed with the debug key.")
    }
}

// The release APK to share is build/app/outputs/flutter-apk/symudol.apk (#153). The Flutter plugin
// copies AGP's output there as app-release.apk, the name `flutter build apk` looks for, so this
// copies that file after assembleRelease rather than renaming AGP's output. Only an APK signed
// with the upload key gets the shareable name: a debug-signed one must never be distributed.
val copySymudolReleaseApk = tasks.register("copySymudolReleaseApk") {
    val apkDir = layout.buildDirectory.dir("outputs/flutter-apk")
    val signedWithUploadKey = hasUploadKey
    // `flutter build apk --split-per-abi` writes app-<abi>-release.apk only, so any app-release.apk
    // in the folder is from an earlier build, perhaps signed with another key.
    val splitPerAbi = providers.gradleProperty("split-per-abi").orNull?.toBoolean() == true
    // Set when the build starts: an app-release.apk older than this was not written by this build.
    val buildStartedAt = System.currentTimeMillis()
    // It reads the Flutter plugin's copy, which Gradle does not track as an output.
    doNotTrackState("Copies the Flutter plugin's untracked app-release.apk")
    doLast {
        val dir = apkDir.get()
        val apk = dir.file("app-release.apk").asFile
        val named = dir.file("symudol.apk").asFile
        // Never leave an earlier build's symudol.apk behind: it is replaced or removed every time.
        if (named.exists() && !named.delete()) {
            throw GradleException("Could not delete the earlier $named.")
        }
        if (!signedWithUploadKey || splitPerAbi) return@doLast
        if (!apk.exists() || apk.lastModified() < buildStartedAt) return@doLast
        apk.copyTo(named)
        // Error level so `flutter build apk`, which hides Gradle's lifecycle output, shows it.
        logger.error("Release APK for distribution: ${named.relativeTo(rootDir.parentFile)}")
    }
}
tasks.matching { it.name == "assembleRelease" }.configureEach { finalizedBy(copySymudolReleaseApk) }

flutter {
    source = "../.."
}

dependencies {
    // BiometricPrompt with a Keystore CryptoObject, for biometric unlock (#23).
    implementation("androidx.biometric:biometric:1.1.0")
    testImplementation("junit:junit:4.13.2")
    testImplementation(kotlin("test"))
    // org.json is bundled in android.jar as a stub; provide the real library so
    // JVM unit tests that call JSON parsing (e.g. Nip55NativeCryptoTest) work.
    testImplementation("org.json:json:20231013")
    // Android components (activities, intents, the ContentProvider) in JVM tests, so NIP-55
    // security behaviour is checked in CI without an emulator (#68).
    testImplementation("org.robolectric:robolectric:4.17")
    testImplementation("androidx.test:core:1.6.1")
}
