plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.shiggy.ddr_md"
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
        applicationId = "com.shiggy.ddr_md"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // NDK Camera2 (native_opencv camera path) requires API 24.
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

 // Handle duplicate native libraries
    packaging {
        jniLibs {
            pickFirsts.add("lib/arm64-v8a/libjpeg.so")
            pickFirsts.add("lib/arm64-v8a/libpng.so")
            pickFirsts.add("lib/arm64-v8a/libpngx.so")
            pickFirsts.add("lib/arm64-v8a/liblept.so")
            pickFirsts.add("lib/arm64-v8a/libleptonica.so")
            pickFirsts.add("lib/arm64-v8a/libtesseract.so")
            pickFirsts.add("lib/arm64-v8a/libc++_shared.so")
            
            pickFirsts.add("lib/armeabi-v7a/libjpeg.so")
            pickFirsts.add("lib/armeabi-v7a/libpng.so")
            pickFirsts.add("lib/armeabi-v7a/libpngx.so")
            pickFirsts.add("lib/armeabi-v7a/liblept.so")
            pickFirsts.add("lib/armeabi-v7a/libleptonica.so")
            pickFirsts.add("lib/armeabi-v7a/libtesseract.so")
            pickFirsts.add("lib/armeabi-v7a/libc++_shared.so")
            
            pickFirsts.add("lib/x86/libjpeg.so")
            pickFirsts.add("lib/x86/libpng.so")
            pickFirsts.add("lib/x86/libpngx.so")
            pickFirsts.add("lib/x86/liblept.so")
            pickFirsts.add("lib/x86/libleptonica.so")
            pickFirsts.add("lib/x86/libtesseract.so")
            pickFirsts.add("lib/x86/libc++_shared.so")
            
            pickFirsts.add("lib/x86_64/libjpeg.so")
            pickFirsts.add("lib/x86_64/libpng.so")
            pickFirsts.add("lib/x86_64/libpngx.so")
            pickFirsts.add("lib/x86_64/liblept.so")
            pickFirsts.add("lib/x86_64/libleptonica.so")
            pickFirsts.add("lib/x86_64/libtesseract.so")
            pickFirsts.add("lib/x86_64/libc++_shared.so")
        }
    }

}

flutter {
    source = "../.."
}
