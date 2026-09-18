import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val keyProperties = Properties()
val keyPropertiesFile = rootProject.file("key.properties")
if (keyPropertiesFile.exists()) {
    keyPropertiesFile.inputStream().use { keyProperties.load(it) }
}
val requiredSigningProperties = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val hasReleaseSigning = keyPropertiesFile.exists() &&
    requiredSigningProperties.all(keyProperties::containsKey)

if (keyPropertiesFile.exists() && !hasReleaseSigning) {
    throw GradleException(
        "android/key.properties must define storeFile, storePassword, keyAlias and keyPassword."
    )
}

if (!hasReleaseSigning) {
    logger.warn(
        "Production signing is not configured; release will use the local debug keystore " +
            "and is not suitable for Play Store upload."
    )
}

android {
    namespace = "com.example.supanotes"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // Override with `-PshareLinkHost=<host>` for each environment. The
    // default keeps local builds usable while production must use the
    // canonical HTTPS Share Link host.
    val shareLinkHost = providers.gradleProperty("shareLinkHost")
        .orElse(providers.environmentVariable("SHARE_LINK_DOMAIN"))
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
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.work:work-runtime-ktx:2.9.1")
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")
}

flutter {
    source = "../.."
}
