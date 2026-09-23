# Flutter ProGuard Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Drift (Database) Rules
-keep class * extends androidx.room.RoomDatabase
-keep class * extends com.google.gson.TypeAdapter
-keep class * extends com.google.gson.JsonSerializer
-keep class * extends com.google.gson.JsonDeserializer

# MapLibre Rules
-keep class com.mapbox.** { *; }

# Sherpa ONNX (Voice) Rules
-keep class com.k2fsa.sherpa.onnx.** { *; }

# Flutter's embedding references Play Core's deferred-components / split-install
# classes (FlutterPlayStoreSplitApplication, PlayStoreDeferredComponentManager),
# but this app doesn't use Play Feature Delivery / dynamic feature modules, so
# the com.google.android.play:core dependency isn't included. Silence R8's
# "missing class" errors for that reference-only code path.
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

-dontwarn java.awt.**
-dontwarn javax.imageio.**
-dontwarn javax.lang.model.**
-dontwarn aQute.bnd.**
-dontwarn org.slf4j.impl.**
