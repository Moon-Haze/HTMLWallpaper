#!/bin/bash
# HTML Wallpaper 构建脚本（vcpkg manifest 模式 + 系统 KF6/Plasma）
#
# 依赖说明：
#   - vcpkg 提供：ecm（Extra CMake Modules）
#   - 系统提供：libplasma（KF6Plasma）、Qt6/QtWebEngine（运行时 QML 模块）
#     安装：sudo pacman -S libplasma qt6-webengine
set -e

# vcpkg 根目录（toolchain 所在），未设置时使用默认位置
export VCPKG_ROOT="${VCPKG_ROOT:-$HOME/.local/share/vcpkg}"

cmake --preset vcpkg
cmake --build --preset vcpkg
cmake --install build

echo "✅ 安装完成：~/.local/share/plasma/wallpapers/de.unkn0wn.htmlwallpaper"
