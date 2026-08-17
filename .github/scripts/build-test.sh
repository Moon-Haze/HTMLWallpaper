#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Moon-Haze
# SPDX-License-Identifier: GPL-2.0-or-later
#
# 多架构共享的「依赖安装 + 配置 + 构建 + 测试 + 安装」脚本。
# 由 .github/workflows/multiarch.yml 的三个架构 job 调用。
#
# 用法: build-test.sh <amd64|arm64|riscv64>
#
# 各架构环境差异:
#   amd64   —— KDE neon 容器(用户 neon,预装 KDE 栈,补装编译器/工具即可)
#   arm64   —— GitHub 原生 ARM runner(Ubuntu 24.04,先接入 KDE neon 源再装依赖)
#   riscv64 —— QEMU 模拟的 Debian 容器(root,实验性;缺 Plasma/KF6/WebEngine 二进制包)

set -euo pipefail

ARCH="${1:?用法: build-test.sh <amd64|arm64|riscv64>}"

# 容器内为 root、runner 为普通用户:统一用 sudo(存在时)
SUDO=()
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null; then
  SUDO=(sudo)
fi

# ================= 1. 依赖安装 =================
case "$ARCH" in
  amd64)
    # 容器基于 Ubuntu noble + 最新 KDE 栈,补装编译工具与 WebEngine 预览依赖。
    # plasma-workspace-dev -> PlasmaConfig.cmake;qt6-declarative-dev-tools -> qmltestrunner。
    "${SUDO[@]}" apt-get update
    "${SUDO[@]}" apt-get install -y --no-install-recommends \
      gcc ninja-build cmake extra-cmake-modules \
      qt6-base-dev qt6-declarative-dev qt6-declarative-dev-tools \
      qt6-webengine-dev plasma-workspace-dev \
      libgl1 libegl1 libglx-mesa0
    ;;
  arm64)
    # 原生 ARM runner(Ubuntu 24.04 arm64):接入 KDE neon unstable(noble)源。
    # neon 源提供 arm64 的 Qt6/KF6/Plasma 最新二进制,与容器镜像同源。
    "${SUDO[@]}" apt-get update
    "${SUDO[@]}" apt-get install -y --no-install-recommends wget gnupg ca-certificates
    "${SUDO[@]}" install -d -m 0755 /etc/apt/keyrings
    echo "deb [signed-by=/etc/apt/keyrings/neon.gpg] https://archive.neon.kde.org/unstable noble main" \
      | "${SUDO[@]}" tee /etc/apt/sources.list.d/neon.list >/dev/null
    wget -qO- https://archive.neon.kde.org/public.key | "${SUDO[@]}" gpg --dearmor -o /etc/apt/keyrings/neon.gpg
    "${SUDO[@]}" apt-get update
    "${SUDO[@]}" apt-get install -y --no-install-recommends \
      gcc ninja-build cmake extra-cmake-modules \
      qt6-base-dev qt6-declarative-dev qt6-declarative-dev-tools \
      qt6-webengine-dev plasma-workspace-dev \
      libgl1 libegl1 libglx-mesa0
    ;;
  riscv64)
    # 实验性:riscv64 无 plasma-workspace-dev / qt6-webengine-dev 二进制包,
    # 只尽力安装基础 Qt6 与工具链;缺失依赖由 configure 阶段暴露并记录日志。
    "${SUDO[@]}" apt-get update || true
    "${SUDO[@]}" apt-get install -y --no-install-recommends \
      gcc g++ ninja-build cmake pkg-config \
      qt6-base-dev qt6-declarative-dev qt6-declarative-dev-tools \
      extra-cmake-modules libgl1 || true
    ;;
  *)
    echo "未知架构: $ARCH" >&2
    exit 2
    ;;
esac

# ================= 2. 实验性架构(riscv64):尽力而为,失败不置红 =================
if [ "$ARCH" = riscv64 ]; then
  # QEMU 模拟下高并发编译过慢且内存压力大,显式限制并行度。
  if ! cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=ON \
      > riscv64-configure.log 2>&1; then
    echo "riscv64 配置失败(缺 KDE/Plasma 依赖,实验性预期),日志末尾:"
    tail -40 riscv64-configure.log
    exit 0
  fi
  if ! cmake --build build --parallel 2 > riscv64-build.log 2>&1; then
    echo "riscv64 构建失败(实验性),日志末尾:"
    tail -40 riscv64-build.log
    exit 0
  fi
  echo "riscv64 配置与构建完成(实验性,未测试/未安装)"
  exit 0
fi

# ================= 3. 正式架构(amd64/arm64):严格门禁 =================
cmake -B build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$HOME/.local" \
  -DBUILD_TESTING=ON
cmake --build build --parallel "$(nproc)"

# C++ 数据层单测(tst_wallpaperproject / model / controller):严格门禁,失败即红灯。
ctest --test-dir build --output-on-failure -R 'tst_wallpaper'

# QML 测试严格门禁:ThumbnailsPanel 已修复,不再容忍失败。
ctest --test-dir build --output-on-failure -R '^tst_' -E 'tst_wallpaper'

# 安装到 staging,供 release job 打包。
cmake --install build --prefix build/staging
