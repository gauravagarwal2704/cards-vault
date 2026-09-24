# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# NFC
-keep class com.gtsz.flutternfckit.** { *; }

# Encryption
-keep class javax.crypto.** { *; }
-keep class javax.crypto.spec.** { *; }

# uCrop (image_cropper) references OkHttp for remote image URIs.
-dontwarn okhttp3.**
-dontwarn okio.**

# Play Core (deferred components)
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Keep generic signature of Call, Response (R8 full mode strips signatures from non-kept items)
-keep,allowobfuscation,allowshrinking interface retrofit2.Call
-keep,allowobfuscation,allowshrinking class retrofit2.Response
-keep,allowobfuscation,allowshrinking class kotlin.coroutines.Continuation

# WorkManager 2.9.1 uses Room 2.5.0 to load this generated database via
# Class.newInstance(). R8 full mode keeps the class name via Room's consumer
# rules, but can still remove its otherwise-unreferenced no-argument constructor.
-keepclassmembers class androidx.work.impl.WorkDatabase_Impl {
    public <init>();
}
