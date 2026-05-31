import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.cyberzeus.ams"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String? ?: "cyberzeus"
            keyPassword = keystoreProperties["keyPassword"] as String? ?: "CyberZeus@2024"
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
                ?: file("cyberzeus-release.jks")
            storePassword = keystoreProperties["storePassword"] as String? ?: "CyberZeus@2024"
        }
    }

    defaultConfig {
        applicationId = "com.cyberzeus.ams"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    applicationVariants.all {
        outputs.forEach { output ->
            (output as com.android.build.gradle.internal.api.BaseVariantOutputImpl)
                .outputFileName = "CyberZeusAMS.apk"
        }
    }
}

flutter {
    source = "../.."
}
