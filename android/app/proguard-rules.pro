# The PDF foreground service is started by name from the manifest and from code;
# keep it (and its Android 15 onTimeout override) exactly as written.
-keep class com.wnm.granthprabandhan.PdfService { *; }
-keep class com.wnm.granthprabandhan.MainActivity { *; }
-keep class com.wnm.granthprabandhan.PageSyncService { *; }
-keep class com.wnm.granthprabandhan.HlFileProvider { *; }

# Round-2: Google sign-in (google_sign_in 7.x → Credential Manager). Keep the Play Services
# credential provider and Google ID classes so R8 can not strip them from release builds.
-if class androidx.credentials.CredentialManager
-keep class androidx.credentials.playservices.** { *; }
-keep class com.google.android.libraries.identity.googleid.** { *; }

# Round-3 (production): R8 is on with resource shrinking. Most libraries ship consumer rules;
# these keep the reflection / JNI entry points that release builds need.
-keepattributes Signature,*Annotation*,InnerClasses,EnclosingMethod,SourceFile,LineNumberTable,Exceptions
# Readable Crashlytics stack traces (mapping is uploaded by the Crashlytics Gradle plugin).
-renamesourcefileattribute SourceFile

# Flutter embedding + plugins (registered by name through GeneratedPluginRegistrant).
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Firebase + Play Services ship their own consumer rules; only silence optional references.
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Credential Manager / google_sign_in.
-keep class * extends androidx.credentials.Credential { *; }
-dontwarn androidx.credentials.**
-dontwarn com.google.android.libraries.identity.googleid.**

# Play Core (Flutter deferred components references these; not used by this app).
-dontwarn com.google.android.play.core.**

# File / share plugins (reflection).
-keep class com.crazecoder.openfile.** { *; }
-keep class dev.fluttercommunity.plus.share.** { *; }

# Kotlin coroutines / metadata used by plugins.
-dontwarn kotlinx.coroutines.**
-keepclassmembers class kotlinx.** { volatile <fields>; }
