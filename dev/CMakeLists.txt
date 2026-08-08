# dev 独立调试程序：config.qml 脱离 plasmashell/KCM 环境运行。
# 纯 C++ + QML：main.cpp 启动，DevShell.qml mock 掉 plasmashell 注入的
# 上下文（wallpaper/configDialog/i18n*/cfg_*），附带 WebEngine 预览。
# 仅供开发分支调试用，不参与 KPackage 打包安装。

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Quick QuickControls2 Qml Widgets WebEngineQuick)

set(CMAKE_AUTOMOC ON)

add_executable(htmlwallpaper-config-dev
    src/main.cpp
    src/DevConfigMap.cpp
    src/DevConfigMap.h
)
target_link_libraries(htmlwallpaper-config-dev PRIVATE
    Qt6::Quick
    Qt6::QuickControls2   # QQuickStyle
    Qt6::Qml
    Qt6::Widgets
    Qt6::WebEngineQuick
    # plasma_wallpaper_htmlwallpaperplugin
)
# 编译期定位 dev/qml/（DevShell.qml 所在目录）与 backend QML 模块产物目录
# （config.qml import com.github.moon_haze.htmlwallpaper；backend 模块落
# ${CMAKE_BINARY_DIR}/bin/<URI>，dev 运行时靠 addImportPath 解析）
target_compile_definitions(htmlwallpaper-config-dev PRIVATE
    DEV_QML_DIR="${CMAKE_CURRENT_SOURCE_DIR}/qml"
    HTMLWALLPAPER_IMPORT_DIR="${CMAKE_BINARY_DIR}/bin"
)
