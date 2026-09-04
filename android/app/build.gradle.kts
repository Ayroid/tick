import java.util.Properties

// Release signing lives outside version control: android/key.properties points
// at the keystore and holds its passwords. Without it, release builds fall back
// to debug keys rather than failing outright.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

base {
    // APK filenames: tick-arm64-v8a-release.apk instead of app-...
    archivesName.set("tick")
}

android {
    namespace = "com.ayroid.tick"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.ayroid.tick"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keystoreProperties.getProperty("storeFile")?.let {
                storeFile = file(it)
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // R8 is deliberately off, as in Wick: it shrinks nothing here and
            // the accessibility service is instantiated by name from the
            // manifest, which is exactly the shape reflection-stripping gets
            // wrong. A blocker that silently stops blocking in release is the
            // worst possible failure for this app.
            signingConfig = if (keystoreProperties.getProperty("storeFile") != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
    // NotificationCompat, for the "that's your time for today" notification.
    // The Flutter embedding pulls androidx.core in transitively; naming it here
    // means the guard does not break the day that changes.
    implementation("androidx.core:core-ktx:1.13.1")

    // Usage.fold is the sum the whole app rests on, and it is a pure function
    // over plain data so it can be checked here rather than on a phone.
    // Run with: (cd android && ./gradlew testDebugUnitTest)
    testImplementation("junit:junit:4.13.2")
}
