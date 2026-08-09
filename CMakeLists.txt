# 3.21：CMakePresets.json（version 6）的最低要求
cmake_minimum_required(VERSION 3.21.0)

project(plasma-htmlwallpaper VERSION 1.0.0)

set(PROJECT_DEP_VERSION "6.6.90")
set(QT_MIN_VERSION "6.10.0")
set(KF6_MIN_VERSION "6.26.0")

include(FeatureSummary)
find_package(ECM ${KF6_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

include(KDEInstallDirs)
include(KDECMakeSettings)
include(KDECompilerSettings NO_POLICY_SCOPE)
include(ECMQtDeclareLoggingCategory)
include(ECMGenerateExportHeader)
include(ECMInstallIcons)
include(KDEPackageAppTemplates)
include(GenerateExportHeader)
include(CMakePackageConfigHelpers)
include(KDEClangFormat)
include(KDEGitCommitHooks)
include(ECMDeprecationSettings)
include(ECMQmlModule)

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core Quick Qml Concurrent)
find_package(Plasma ${PROJECT_DEP_VERSION} REQUIRED)

plasma_install_package(package com.github.moon_haze.htmlwallpaper wallpapers wallpaper)

# 壁纸数据目录独立于 KPackage 安装
# 本地开发（CMAKE_INSTALL_PREFIX=~/.local）→ ~/.local/share/html-wallpapers
# Arch 包（CMAKE_INSTALL_PREFIX=/usr）→ /usr/share/html-wallpapers
install(DIRECTORY html-wallpapers/ DESTINATION share/html-wallpapers)

# C++ 后端 QML 模块（com.github.moon_haze.htmlwallpaper）：替代旧 HtmlWallpaperParser.qml
add_subdirectory(./plugin)

# dev 独立调试程序（开发分支 dev/config-app）：config.qml 脱离 plasmashell
# 运行 + WebEngine 预览。不参与 KPackage 安装，仅供开发调试。
add_subdirectory(./dev)

# 测试注册在 tests/CMakeLists.txt（含 include(CTest)）；顶层必须 enable_testing()
# 才能生成顶层 CTestTestfile.cmake 并递归到 tests/（否则 ctest 从 build/ 读不到测试）
enable_testing()

add_subdirectory(./test)
