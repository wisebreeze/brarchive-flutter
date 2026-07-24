# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Keep native method channel handlers
-keep class com.wisebreeze.brarchive.** { *; }

# Keep dynamic_color plugin
-keep class com.github.matterapp.dynamiccolors.** { *; }

# Keep shared_preferences
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# Keep url_launcher
-keep class io.flutter.plugins.urllauncher.** { *; }

# Keep path_provider
-keep class io.flutter.plugins.pathprovider.** { *; }

# Standard Flutter ProGuard rules
-dontwarn android.**
