plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.supanotes"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // Override with `-PshareLinkHost=<host>` for each environment. The
    // default keeps local builds usable while production must use the
    // canonical HTTPS Share Link host.
    val shareLinkHost = providers.gradleProperty("shareLinkHost")
        .orElse("supanotes.app")

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.supanotes"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["shareLinkHost"] = shareLinkHost.get()
    }

    signingConfigs {
        create("release") {
            providers.gradleProperty("releaseStoreFile").orNull?.let { storeFile = file(it) }
            storePassword = providers.gradleProperty("releaseStorePassword").orNull
            keyAlias = providers.gradleProperty("releaseKeyAlias").orNull
            keyPassword = providers.gradleProperty("releaseKeyPassword").orNull
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
