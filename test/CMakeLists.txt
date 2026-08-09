
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
        file(GLOB QML_TEST_FILES CONFIGURE_DEPENDS "${CMAKE_CURRENT_SOURCE_DIR}/tst_*.qml")
        foreach(test_file ${QML_TEST_FILES})
            get_filename_component(test_name ${test_file} NAME_WE)
            add_test(
                NAME ${test_name}
                COMMAND ${QMLTESTRUNNER_EXECUTABLE}
                        -import ${CMAKE_BINARY_DIR}/bin
                        -input ${test_file}
            )
            # offscreen：无显示环境下跑 QML；-import/QML2_IMPORT_PATH：让
            # com.github.moon_haze.htmlwallpaper 模块（backend 构建产物）可被解析。
            set_tests_properties(${test_name} PROPERTIES
                ENVIRONMENT "QT_QPA_PLATFORM=offscreen;QML2_IMPORT_PATH=${CMAKE_BINARY_DIR}/bin"
                WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
            )
        endforeach()
    else()
        message(WARNING "未找到 qmltestrunner，跳过 QML 测试（需要安装 qt6-declarative 的测试工具）")
    endif()

    # C++ 数据层单测（QTest）：编译 plugin 下纯数据层源文件，不依赖 QML/KF6。
    # qt_add_executable 自动开启 AUTOMOC（WallpaperProperty 无 Q_OBJECT，但后续
    # 任务会把带 Q_OBJECT 的 WallpaperPropertyItem/Model 加进来）。
    find_package(Qt6 ${QT_MIN_VERSION} REQUIRED COMPONENTS Test)
    qt_add_executable(tst_wallpaperproject tst_wallpaperproject.cpp)
    target_sources(tst_wallpaperproject PRIVATE
        ../plugin/wallpaperproperty.cpp
        ../plugin/wallpaperproject.cpp
        ../plugin/wallpaperpropertyitem.cpp
        ../plugin/wallpaperpropertymodel.cpp
    )
    # 让 tst_*.cpp 能 #include "wallpaperproperty.h" 等 plugin 下的头文件
    target_include_directories(tst_wallpaperproject PRIVATE ../plugin)
    target_link_libraries(tst_wallpaperproject PRIVATE Qt6::Test Qt6::Core)
    add_test(NAME tst_wallpaperproject COMMAND tst_wallpaperproject)
    # WORKING_DIRECTORY 设为 tests/ 目录，让 data/wallpapers fixtures 相对路径可用
    set_tests_properties(tst_wallpaperproject PROPERTIES
        WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
    )
endif()
