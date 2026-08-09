
add_library(plasma_wallpaper_htmlwallpaperplugin_debug STATIC)
set_property(TARGET plasma_wallpaper_htmlwallpaperplugin_debug PROPERTY POSITION_INDEPENDENT_CODE ON)
target_link_libraries(plasma_wallpaper_htmlwallpaperplugin_debug
    Qt::Core
)
ecm_qt_declare_logging_category(plasma_wallpaper_htmlwallpaperplugin_debug
    HEADER debug.h
    IDENTIFIER WALLPAPERHTMLWALLPAPER
    CATEGORY_NAME kde.wallpapers.htmlwallpaper
    DEFAULT_SEVERITY Info
    DESCRIPTION "Wallpaper plugins"
    EXPORT KDEPLASMAADDONS
)

ecm_add_qml_module(plasma_wallpaper_htmlwallpaperplugin
    URI "com.github.moon_haze.htmlwallpaper"
    VERSION 1.0
    GENERATE_PLUGIN_SOURCE
    DEPENDENCIES QtQml QtQuick
)

target_sources(plasma_wallpaper_htmlwallpaperplugin PRIVATE
    htmlbackend.cpp
    wallpaperitem.cpp
    wallpaperlistmodel.cpp
    wallpaperpropertymodel.cpp
)

target_link_libraries(plasma_wallpaper_htmlwallpaperplugin PRIVATE
    Qt6::Concurrent   # QtConcurrent::run 后台扫描
    Qt6::Core
    Qt6::Qml          # QJSEngine（evaluateCondition）
    Qt6::Quick
    plasma_wallpaper_htmlwallpaperplugin_debug
)

ecm_finalize_qml_module(plasma_wallpaper_htmlwallpaperplugin)

