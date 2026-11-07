import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties (gitignored, never committed) points at the
// keystore. A release build without it FAILS (Play rejects debug-signed bundles); debug
// builds don't need it.
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val hasReleaseKey = keyProps.getProperty("storeFile")?.let { file(it).exists() } == true
// Google login needs the Satlok key's SHA on every build (debug too): never the default debug key.
if (!hasReleaseKey && gradle.startParameter.taskNames.any { t ->
        listOf("assemble", "bundle", "install", "package", "Release", "Debug").any { t.contains(it, ignoreCase = true) }
    }) {
    throw GradleException(
        "android/key.properties (Satlok upload key) is missing or its storeFile does not exist. " +
            "Every APK/AAB (debug and release) must be signed with it so Google login works; " +
            "the default debug key is never used.",
    )
}

android {
    namespace = "com.wnm.granthprabandhan"
    // Play requires targetSdk ≥ 35; pinned so a Flutter SDK change can not lower it.
    compileSdk = maxOf(flutter.compileSdkVersion, 36)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.wnm.granthprabandhan"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = maxOf(flutter.targetSdkVersion, 36)
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            // Same Satlok key as release (its SHA is registered for Google sign-in).
            if (hasReleaseKey) signingConfig = signingConfigs.getByName("release")
        }
        release {
            // Never the debug key: without key.properties the release build already failed above.
            if (hasReleaseKey) signingConfig = signingConfigs.getByName("release")
            // Production: R8 code shrinking + resource shrinking, never debuggable.
            isMinifyEnabled = true
            isShrinkResources = true
            isDebuggable = false
            isJniDebuggable = false
            // Added to Flutter's own R8 rules: app services, Firebase, sign-in, PDF.
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // JVM unit tests of the native PDF notification helpers (android/app/src/test).
    testImplementation("junit:junit:4.13.2")
    // android.jar only has stubs of org.json; the transfer tests need the real parser.
    testImplementation("org.json:json:20240303")
}

// Firebase config is kept out of git; CI builds without it (Firebase then stays off at runtime).
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
    apply(plugin = "com.google.firebase.crashlytics")
}
