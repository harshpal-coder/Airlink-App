# Flutter Background Service
-keep class id.flutter.flutter_background_service.** { *; }

# Nearby Connections
-keep class com.google.android.gms.nearby.** { *; }
-keep class com.google.android.gms.common.** { *; }

# Keep Flutter entrypoints
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# Keep Dart VM entry points
-keepattributes SourceFile,LineNumberTable,*Annotation*

# Google Play Core (suppress warnings for missing deferred components)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task

# Keep all R classes and their fields to prevent resource stripping
-keep class **.R { *; }
-keep class **.R$* { *; }
-keep class com.example.app.R { *; }
-keep class com.example.app.R$* { *; }
-keepclassmembers class **.R$* {
    public static <fields>;
}



# sqflite
-keep class net.sqlcipher.** { *; }
-keep class com.tekartik.sqflite.** { *; }

# permission_handler
-keep class com.baseflow.permissionhandler.** { *; }

# flutter_local_notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.google.firebase.messaging.** { *; }

# geolocator
-keep class com.baseflow.geolocator.** { *; }

# google_fonts
-keep class com.google.android.gms.identity.** { *; }
-keep class com.google.android.gms.common.** { *; }

# device_info_plus
-keep class dev.fluttercommunity.plus.device_info.** { *; }

# audioplayers
-keep class xyz.luan.audioplayers.** { *; }

# record
-keep class com.llfbandit.record.** { *; }

# gal
-keep class com.github.tshion.gal.** { *; }

# file_picker
-keep class com.mr.flutter.plugin.filepicker.** { *; }

# share_plus
-keep class dev.fluttercommunity.plus.share.** { *; }

# nearby_connections (already partially covered but being safe)
-keep class com.google.android.gms.nearby.** { *; }

# Flutter internal classes (additional safety)
-keep class io.flutter.plugin.editing.** { *; }
-keep class io.flutter.plugin.common.** { *; }
-keep class io.flutter.embedding.engine.plugins.** { *; }



