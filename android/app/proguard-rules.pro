# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Google Maps
-keep class com.google.android.gms.maps.** { *; }
-keep class com.google.android.libraries.maps.** { *; }

# Supabase (Postgrest, GoTrue, etc.)
-keep class io.github.jan.supabase.** { *; }
-keep class io.ktor.** { *; }
-keep class kotlinx.serialization.** { *; }

# Keep models to prevent serialization issues
-keep class com.familytracker.app.models.** { *; }

# Optimization
-optimizationpasses 5
-dontusemixedcaseclassnames
-dontskipnonpubliclibraryclasses
-dontpreverify
-verbose

# Fix R8 missing classes for Play Core (common in Flutter release builds)
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Fix R8 missing classes for Google Play Services if needed
-dontwarn com.google.android.gms.**

