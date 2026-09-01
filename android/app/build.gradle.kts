import java.util.Properties

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}
val developmentOnlySigning =
    keystoreProperties.getProperty("developmentOnly", "false").toBoolean()
val requestedTaskNames = gradle.startParameter.taskNames.map {
    it.substringAfterLast(':').lowercase()
}
val releaseArtifactRequested = requestedTaskNames.any { taskName ->
    taskName.contains("release") ||
        taskName == "build" ||
        taskName == "assemble" ||
        taskName == "bundle"
}
val developmentSigningForbidden = requestedTaskNames.any { taskName ->
    taskName == "build" ||
        taskName == "assemble" ||
        taskName == "bundle" ||
        (taskName.contains("bundle") && taskName.contains("release"))
}

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android Gradle plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.leongziqi.hikercircle"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.leongziqi.hikercircle"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        val localProperties = Properties()
        val localPropertiesFile = rootProject.file("local.properties")
        if (localPropertiesFile.exists()) {
            localPropertiesFile.inputStream().use { localProperties.load(it) }
        }
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] =
            localProperties.getProperty("google.maps.apiKey", "")
        buildConfigField(
            "boolean",
            "DEVELOPMENT_ONLY_SIGNING",
            developmentOnlySigning.toString(),
        )
    }

    buildFeatures {
        buildConfig = true
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        debug {
            // Debug build will use Android default debug signing
            signingConfig = signingConfigs.getByName("debug")
        }

        release {
            val releaseSigning = signingConfigs.findByName("release")
            if (releaseSigning != null) {
                if (
                    developmentOnlySigning &&
                    releaseArtifactRequested &&
                    developmentSigningForbidden
                ) {
                    throw GradleException(
                        "The configured Android signing key is for local release-mode APK testing only. " +
                            "Replace android/key.properties with a production upload key before building " +
                            "an app bundle or another release artifact."
                    )
                }
                signingConfig = releaseSigning
            } else if (releaseArtifactRequested) {
                throw GradleException(
                    "Release signing is not configured. Add android/key.properties and a release keystore before building a release artifact."
                )
            }
        }
    }
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:34.17.0"))
    implementation("com.google.firebase:firebase-firestore")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.camera:camera-camera2:1.4.2")
    implementation("androidx.camera:camera-lifecycle:1.4.2")
    implementation("androidx.camera:camera-view:1.4.2")
    implementation("com.google.guava:guava:33.4.8-android")
    implementation("com.google.mlkit:barcode-scanning:17.3.0")
}

flutter {
    source = "../.."
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
