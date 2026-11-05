plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing comes from environment variables set by CI from GitHub
// Secrets (or by you locally). Nothing secret is ever stored in this repo.
val releaseKeystorePath: String? = System.getenv("WL_KEYSTORE_PATH")

android {
    namespace = "app.watchedledger"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "app.watchedledger"
        // 24 = Android 7.0; required by the secure key storage library.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseKeystorePath != null) {
            create("release") {
                storeFile = file(releaseKeystorePath)
                storePassword = System.getenv("WL_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("WL_KEY_ALIAS")
                keyPassword = System.getenv("WL_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            // Without a keystore (e.g. a quick local build) fall back to the
            // debug key. CI refuses to publish a Release signed this way.
            signingConfig = if (releaseKeystorePath != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    // Don't embed Google's encrypted dependency-metadata block in the APK.
    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
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
