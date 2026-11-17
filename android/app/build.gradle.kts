import java.util.Properties

plugins {
  id("com.android.application")
  id("kotlin-android")
  // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
  id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties =
  Properties().apply {
    if (keystorePropertiesFile.exists()) {
      keystorePropertiesFile.inputStream().use { load(it) }
    }
  }

android {
  namespace = "com.phonoliteorg.phonolite_app"
  compileSdk = flutter.compileSdkVersion
  ndkVersion = flutter.ndkVersion

  compileOptions {
    sourceCompatibility = JavaVersion.VERSION_11
    targetCompatibility = JavaVersion.VERSION_11
  }

  kotlinOptions {
    jvmTarget = JavaVersion.VERSION_11.toString()
  }

  defaultConfig {
    applicationId = "com.phonoliteorg.phonolite_app"
    // You can update the following values to match your application needs.
    // For more information, see: https://flutter.dev/to/review-gradle-config.
    minSdk = flutter.minSdkVersion
    targetSdk = flutter.targetSdkVersion
    versionCode = flutter.versionCode
    versionName = flutter.versionName
  }

  signingConfigs {
    create("release") {
      keyAlias = keystoreProperties.getProperty("keyAlias")
      keyPassword = keystoreProperties.getProperty("keyPassword")
      storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
      storePassword = keystoreProperties.getProperty("storePassword")
    }
  }

  buildTypes {
    release {
      signingConfig = signingConfigs.getByName("release")
    }
  }
}

dependencies {
  implementation("androidx.core:core-ktx:1.13.1")
  implementation("androidx.media:media:1.7.0")
}

flutter {
  source = "../.."
}

// Fail only when a release artifact is actually signed, so debug, profile and
// compile-only tasks still configure without the upload keystore.
gradle.taskGraph.whenReady {
  val signsRelease =
    allTasks.any { task ->
      task.project == project &&
        task.name in setOf("packageRelease", "bundleRelease", "signReleaseBundle", "validateSigningRelease")
    }
  if (signsRelease && !keystorePropertiesFile.exists()) {
    throw GradleException(
      "Release signing needs ${keystorePropertiesFile.path} with storeFile, storePassword, keyAlias and keyPassword. " +
        "See https://docs.flutter.dev/deployment/android#configure-signing-in-gradle.",
    )
  }
}

val copyReleaseApk by tasks.registering(Copy::class) {
  dependsOn("assembleRelease")
  val apkOutputDir = layout.buildDirectory.dir("outputs/apk/release")
  val flutterOutputDir = layout.buildDirectory.dir("outputs/flutter-apk")

  into(flutterOutputDir)
  from(apkOutputDir.map { it.file("app-release.apk") })
  from(apkOutputDir.map { it.file("app-release.apk") }) {
    rename { "phonolite-release.apk" }
  }
}

tasks.matching { it.name == "assembleRelease" }.configureEach {
  finalizedBy(copyReleaseApk)
}
