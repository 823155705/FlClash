
-keep class com.follow.clash.models.** { *; }

-keep class com.follow.clash.service.models.** { *; }

# Widget / HyperOS (Gson reflection + AppWidgetProvider entry points)
-keep class com.follow.clash.WidgetState { *; }
-keep class com.follow.clash.WidgetDataStore { *; }
-keep class com.follow.clash.WidgetRefresher { *; }
-keep class com.follow.clash.WidgetProvider { *; }
-keep class com.follow.clash.WidgetProviderWide { *; }
-keep class com.follow.clash.WidgetUi { *; }
-keep class com.follow.clash.plugins.WidgetPlugin { *; }
-keep class com.follow.clash.hyperos.** { *; }

-keepclassmembers class com.follow.clash.WidgetState {
    <fields>;
    <init>(...);
}

# flutter_rust_bridge / rquickjs
-keep class com.flin.** { *; }
-keep class com.follow.clash.rust.** { *; }
