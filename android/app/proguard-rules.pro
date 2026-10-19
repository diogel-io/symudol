# Release builds write no debug or verbose lines to the system log (SR-21, diogel-io/symudol#14).
# DiogelLog already drops its debug lines at compile time; this also removes any other
# Log.v/d/i call that reaches the release build.
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
}
