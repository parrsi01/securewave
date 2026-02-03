import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.securewave_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.securewave_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val keystoreProperties = Properties()
    val keystorePropertiesFile = rootProject.file("key.properties")
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
    }

    val envStoreFile = System.getenv("ANDROID_KEYSTORE_PATH")
    val envStorePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
    val envKeyAlias = System.getenv("ANDROID_KEY_ALIAS")
    val envKeyPassword = System.getenv("ANDROID_KEY_PASSWORD")

    fun resolveProp(name: String, envValue: String?): String? {
        val value = keystoreProperties.getProperty(name)
        return if (!value.isNullOrBlank()) value else envValue
    }

    val storeFileValue = resolveProp("storeFile", envStoreFile)
    val storePasswordValue = resolveProp("storePassword", envStorePassword)
    val keyAliasValue = resolveProp("keyAlias", envKeyAlias)
    val keyPasswordValue = resolveProp("keyPassword", envKeyPassword)

    // Guard against unsigned release builds by requiring explicit signing config.
    val releaseSigningConfigured = !storeFileValue.isNullOrBlank() &&
        !storePasswordValue.isNullOrBlank() &&
        !keyAliasValue.isNullOrBlank() &&
        !keyPasswordValue.isNullOrBlank()

    signingConfigs {
        create("release") {
            if (releaseSigningConfigured) {
                storeFile = file(storeFileValue!!)
                storePassword = storePasswordValue
                keyAlias = keyAliasValue
                keyPassword = keyPasswordValue
            }
        }
    }

    buildTypes {
        release {
            val isReleaseTask = gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
            if (releaseSigningConfigured) {
                signingConfig = signingConfigs.getByName("release")
            } else if (isReleaseTask) {
                throw GradleException(
                    "Release signing is not configured. Provide android/key.properties or ANDROID_KEYSTORE_* env vars. See ANDROID_VPN_SETUP.md."
                )
            } else {
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.wireguard.android:tunnel:1.0.20260102")
}
