# kotlinx.serialization keeps its generated serializers on the companion of each
# @Serializable class; R8 needs them reachable.
-keepclassmembers class **$$serializer { *; }
-keepclasseswithmembers class ** {
    kotlinx.serialization.KSerializer serializer(...);
}

# Methods a WebView calls back into are only reachable through the JavaScript bridge, so R8 sees
# them as unused and renames or removes them. Without this rule the release build's bridge breaks
# while debug keeps working.
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# OkHttp references optional platform APIs that are absent at runtime.
-dontwarn okhttp3.internal.platform.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
