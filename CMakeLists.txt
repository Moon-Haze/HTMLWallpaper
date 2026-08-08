# 3.21：CMakePresets.json（version 6）的最低要求
cmake_minimum_required(VERSION 3.21.0)

project(plasma-htmlwallpaper VERSION 1.0.0)

set(PROJECT_DEP_VERSION "6.6.90")
set(QT_MIN_VERSION "6.10.0")
set(KF6_MIN_VERSION "6.26.0")

find_package(ECM ${KF6_MIN_VERSION} REQUIRED NO_MODULE)
set(CMAKE_MODULE_PATH ${ECM_MODULE_PATH})

find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Core Quick)
find_package(Plasma ${PROJECT_DEP_VERSION} REQUIRED)

plasma_install_package(package com.github.Moon-Haze.htmlwallpaper wallpapers wallpaper)

# 壁纸数据目录独立于 KPackage 安装
# 本地开发（CMAKE_INSTALL_PREFIX=~/.local）→ ~/.local/share/html-wallpapers
# Arch 包（CMAKE_INSTALL_PREFIX=/usr）→ /usr/share/html-wallpapers
install(DIRECTORY html-wallpapers/ DESTINATION share/html-wallpapers)

# ---- 测试（Qt Quick Test / qmltestrunner）----
include(CTest)

if(BUILD_TESTING)
    # 注意：/usr/bin/qmltestrunner 常是 Qt5（qt5-declarative）版本，对 Qt6 测试
    # 静默失败。必须用 Qt6 工具目录（与 qmake 同目录）里的 Qt6 版本。
    get_target_property(_qt6_qmake Qt6::qmake IMPORTED_LOCATION)
    if(_qt6_qmake)
        get_filename_component(_qt6_bin_dir "${_qt6_qmake}" DIRECTORY)
        find_program(QMLTESTRUNNER_EXECUTABLE NAMES qmltestrunner
                     HINTS "${_qt6_bin_dir}")
    else()
        find_program(QMLTESTRUNNER_EXECUTABLE NAMES qmltestrunner)
    endif()
    if(QMLTESTRUNNER_EXECUTABLE)
        # 收集 tests/ 下的测试文件（tst_*.qml）。CONFIGURE_DEPENDS 让新增/删除
        # 测试文件时自动触发重新配置，无需手动 rerun cmake。
        file(GLOB QML_TEST_FILES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/tests/tst_*.qml")
        foreach(test_file ${QML_TEST_FILES})
            get_filename_component(test_name ${test_file} NAME_WE)
            add_test(
                NAME ${test_name}
                COMMAND ${QMLTESTRUNNER_EXECUTABLE} -input ${test_file}
            )
            # offscreen：无显示环境下跑 QML；QML_XHR_ALLOW_FILE_READ：允许解析器读本地 JSON
            set_tests_properties(${test_name} PROPERTIES
                ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QML_XHR_ALLOW_FILE_READ=1"
                WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/tests"
            )
        endforeach()
    else()
        message(WARNING "未找到 qmltestrunner，跳过 QML 测试（需要安装 qt6-declarative 的测试工具）")
    endif()
endif()
