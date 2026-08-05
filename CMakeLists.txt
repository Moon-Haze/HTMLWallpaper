cmake_minimum_required(VERSION 3.16.0)

project(plasma-htmlwallpaper)

set(PROJECT_DEP_VERSION "6.6.90")
set(QT_MIN_VERSION "6.10.0")
set(KF6_MIN_VERSION "6.26.0")
set(KDE_COMPILERSETTINGS_LEVEL "6.14")

find_package(ECM ${KF6_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

find_package(Plasma ${PROJECT_DEP_VERSION} REQUIRED)

plasma_install_package(package com.github.Moon-Haze.htmlwallpaper wallpapers wallpaper)
