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
        applicationId = if (System.getenv("HC_CAPTURE_ONLY") == "1") "com.leongziqi.hikercircle.showcase" else "com.leongziqi.hikercircle"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        buildConfigField("boolean", "CAPTURE_ONLY", (System.getenv("HC_CAPTURE_ONLY") == "1").toString())
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
            proguardFile("proguard-rules.pro")
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
    implementation("net.zetetic:sqlcipher-android:4.10.0@aar")
    implementation("androidx.sqlite:sqlite:2.5.2")
    implementation(platform("com.google.firebase:firebase-bom:34.17.0"))
    implementation("com.google.firebase:firebase-firestore")
    implementation("com.google.firebase:firebase-auth")
    implementation("com.google.firebase:firebase-functions")
    implementation("com.google.firebase:firebase-appcheck-playintegrity")
    if (developmentOnlySigning) {
        // Local release-mode testing uses a registered per-installation token.
        implementation("com.google.firebase:firebase-appcheck-debug")
    } else {
        debugImplementation("com.google.firebase:firebase-appcheck-debug")
    }
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

if (System.getenv("HC_CAPTURE_ONLY") == "1") {
    tasks.configureEach {
        if (name.contains("GoogleServices")) enabled = false
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}
