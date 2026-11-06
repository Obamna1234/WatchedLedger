# R8 rules for WatchedLedger release builds.
# Flutter and its plugins ship their own keep rules; these only silence
# warnings for optional classes that are never used by this app.

# Flutter's deferred-components support references Play Core, which this app
# (distributed outside Google Play) does not include.
-dontwarn com.google.android.play.core.**

# Strip verbose/debug logging calls from release builds.
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
}
