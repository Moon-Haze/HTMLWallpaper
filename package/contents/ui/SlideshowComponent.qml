/*
    SPDX-FileCopyrightText: 2013 Marco Martin <mart@kde.org>
    SPDX-FileCopyrightText: 2014 Kai Uwe Broulik <kde@privat.broulik.de>
    SPDX-FileCopyrightText: 2019 David Redondo <kde@david-redondo.de>

    SPDX-License-Identifier: GPL-2.0-or-later
*/
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.plasma.wallpapers.image as PlasmaWallpaper

/**
 * 幻灯片模式配置面板（HTMLWallpaper 模式下显示）。
 *
 * 上半部分：轮播排序方式（随机 / 按名称 / 按修改时间）与切换间隔（时/分/秒）；
 * 下半部分左栏：轮播文件夹列表（可增删、打开目录）；
 * 下半部分右栏：加载 ThumbnailsComponent 展示所有可勾选的壁纸。
 * 所有控件直接读写配置绑定属性（cfg_*），由 KCM 框架负责持久化。
 *
 * For proper alignment, an ancestor **MUST** have id "appearanceRoot" and property "parentLayout"
 */
ColumnLayout {
    id: slideshowComponent
    property var configuration: wallpaper.configuration
    property var screenSize: Qt.size(Screen.width, Screen.height)

    // 把 cfg_SlideInterval（秒）拆成时/分/秒三段，供三个 SpinBox 分别显示
    property int hoursIntervalValue: Math.floor(cfg_SlideInterval / 3600)
    property int minutesIntervalValue: Math.floor(cfg_SlideInterval % 3600) / 60
    property int secondsIntervalValue: cfg_SlideInterval % 3600 % 60

    // 各段对应的默认值（用于高亮未改动项）
    property int hoursIntervalValueDefault: Math.floor(cfg_SlideIntervalDefault / 3600)
    property int minutesIntervalValueDefault: Math.floor(cfg_SlideIntervalDefault % 3600) / 60
    property int secondsIntervalValueDefault: cfg_SlideIntervalDefault % 3600 % 60

    // 配置变化时同步回对应 SpinBox 的显示值
    onHoursIntervalValueChanged: hoursInterval.value = hoursIntervalValue
    onMinutesIntervalValueChanged: minutesInterval.value = minutesIntervalValue
    onSecondsIntervalValueChanged: secondsInterval.value = secondsIntervalValue

    spacing: 0

    Kirigami.FormLayout {
        id: form

        Layout.bottomMargin: Kirigami.Units.largeSpacing

        // 与上层“外观”设置页对齐同一列标签宽度
        Component.onCompleted: function () {
            if (typeof appearanceRoot !== "undefined") {
                twinFormLayouts = appearanceRoot.parentLayout;
            }
        }

        // —— 轮播排序方式下拉框 ——
        RowLayout {
            id: slideshowModeRow
            Kirigami.FormData.label: i18nd("plasma_wallpaper_org.kde.image", "Order:")

            QQC2.ComboBox {
                id: slideshowModeComboBox

                // 候选排序方式：随机 / A→Z / Z→A / 按修改时间
                model: [
                    {
                        'label': i18nd("plasma_wallpaper_org.kde.image", "Random"),
                        'slideshowMode':  PlasmaWallpaper.SortingMode.Random
                    },
                    {
                        'label': i18nd("plasma_wallpaper_org.kde.image", "A to Z"),
                        'slideshowMode':  PlasmaWallpaper.SortingMode.Alphabetical
                    },
                    {
                        'label': i18nd("plasma_wallpaper_org.kde.image", "Z to A"),
                        'slideshowMode':  PlasmaWallpaper.SortingMode.AlphabeticalReversed
                    },
                    {
                        'label': i18nd("plasma_wallpaper_org.kde.image", "Date modified (newest first)"),
                        'slideshowMode':  PlasmaWallpaper.SortingMode.ModifiedReversed
                    },
                    {
                        'label': i18nd("plasma_wallpaper_org.kde.image", "Date modified (oldest first)"),
                        'slideshowMode':  PlasmaWallpaper.SortingMode.Modified
                    }
                ]
                textRole: "label"
                // 用户选择后写入排序模式配置
                onActivated: {
                    cfg_SlideshowMode = model[currentIndex]["slideshowMode"];
                }
                Component.onCompleted: setMethod();
                // 初始化：根据当前配置选中对应选项
                function setMethod() {
                    for (var i = 0; i < model.length; i++) {
                        if (model[i]["slideshowMode"] === configuration.SlideshowMode) {
                            slideshowModeComboBox.currentIndex = i;
                            break;
                        }
                    }
                }

                // 非默认值时高亮，提示用户该设置已改动
                KCM.SettingHighlighter {
                    highlight: cfg_SlideshowMode != cfg_SlideshowModeDefault
                }
            }

            // “按文件夹分组”开关：优先播完一个文件夹再播下一个
            QQC2.CheckBox {
                id: slideshowFoldersFirstCheckBox
                text: i18nd("plasma_wallpaper_org.kde.image", "Group by folders")
                checked: root.cfg_SlideshowFoldersFirst
                onToggled: cfg_SlideshowFoldersFirst = slideshowFoldersFirstCheckBox.checked

                KCM.SettingHighlighter {
                    highlight: root.cfg_SlideshowFoldersFirst !== cfg_SlideshowFoldersFirstDefault
                }
            }
        }

        // —— 轮播切换间隔：时 / 分 / 秒 三个 SpinBox ——
        // FIXME: there should be only one spinbox: QtControls spinboxes are still too limited for it tough
        RowLayout {
            Kirigami.FormData.label: i18nd("plasma_wallpaper_org.kde.image", "Change every:")
            QQC2.SpinBox {
                id: hoursInterval
                value: slideshowComponent.hoursIntervalValue
                from: 0
                to: 24
                editable: true
                // 任一段改动都重组 cfg_SlideInterval（秒），并写回配置
                onValueChanged: cfg_SlideInterval = hoursInterval.value * 3600 + minutesInterval.value * 60 + secondsInterval.value

                textFromValue: function(value, locale) {
                    return i18ndp("plasma_wallpaper_org.kde.image","%1 hour", "%1 hours", value)
                }
                valueFromText: function(text, locale) {
                    return parseInt(text);
                }

                KCM.SettingHighlighter {
                    highlight: slideshowComponent.hoursIntervalValue != slideshowComponent.hoursIntervalValueDefault
                }
            }

            QQC2.SpinBox {
                id: minutesInterval
                value: slideshowComponent.minutesIntervalValue
                from: 0
                to: 60
                editable: true
                onValueChanged: cfg_SlideInterval = hoursInterval.value * 3600 + minutesInterval.value * 60 + secondsInterval.value

                textFromValue: function(value, locale) {
                    return i18ndp("plasma_wallpaper_org.kde.image","%1 minute", "%1 minutes", value)
                }
                valueFromText: function(text, locale) {
                    return parseInt(text);
                }

                KCM.SettingHighlighter {
                    highlight: slideshowComponent.minutesIntervalValue != slideshowComponent.minutesIntervalValueDefault
                }
            }

            QQC2.SpinBox {
                id: secondsInterval
                value: slideshowComponent.secondsIntervalValue
                // 时与分都为 0 时，秒最小值为 1，保证间隔不为 0（否则立即闪切）
                from: slideshowComponent.hoursIntervalValue === 0 && slideshowComponent.minutesIntervalValue === 0 ? 1 : 0
                to: 60
                editable: true
                onValueChanged: cfg_SlideInterval = hoursInterval.value * 3600 + minutesInterval.value * 60 + secondsInterval.value

                textFromValue: function(value, locale) {
                    return i18ndp("plasma_wallpaper_org.kde.image","%1 second", "%1 seconds", value)
                }
                valueFromText: function(text, locale) {
                    return parseInt(text);
                }

                KCM.SettingHighlighter {
                    highlight: slideshowComponent.secondsIntervalValue != slideshowComponent.secondsIntervalValueDefault
                }
            }
        }
    }

    RowLayout {

        spacing: 0

        // —— 左栏：轮播文件夹列表 ——
        ColumnLayout {
            spacing: 0
            Layout.maximumWidth: Kirigami.Units.gridUnit * 16

            Kirigami.Separator {
                Layout.fillWidth: true
            }
            QQC2.ScrollView {
                id: foldersScroll
                Layout.fillWidth: true
                Layout.fillHeight: true

                // 用主题背景色，视觉上把列表区与设置区区分开
                background: Rectangle {
                    Kirigami.Theme.inherit: false
                    Kirigami.Theme.colorSet: Kirigami.Theme.View
                    color: Kirigami.Theme.backgroundColor
                }

                // 轮播路径列表：数据源是 ImageBackend 的 slidePaths
                ListView {
                    id: slidePathsView
                    headerPositioning: ListView.OverlayHeader
                    // 悬浮标题栏，含“添加文件夹”按钮
                    header: Kirigami.InlineViewHeader {
                        width: slidePathsView.width
                        text: i18nd("plasma_wallpaper_org.kde.image", "Folders")
                        actions: [
                            Kirigami.Action {
                                icon.name: "list-add-symbolic"
                                text: i18ndc("plasma_wallpaper_org.kde.image", "@action button the thing being added is a folder", "Add…")
                                Accessible.name: i18ndc("plasma_wallpaper_org.kde.image", "@action:button", "Add Folder…")
                                onTriggered: root.openChooserDialog()
                            }
                        ]
                    }
                    model: imageWallpaper.slidePaths
                    delegate: Kirigami.SubtitleDelegate {
                        id: baseListItem

                        required property var modelData

                        width: slidePathsView.width
                        // Don't need a highlight or hover effects
                        // 列表项无需悬停高亮效果
                        hoverEnabled: false
                        down: false

                        // 主标题只显示文件夹名（去掉末尾斜杠后取最后一段）
                        text: {
                            var strippedPath = baseListItem.modelData.replace(/\/+$/, "");
                            return strippedPath.split('/').pop()
                        }
                        // Subtitle: the path to the folder
                        // 副标题显示父目录路径
                        subtitle: {
                            var strippedPath = baseListItem.modelData.replace(/\/+$/, "");
                            return strippedPath.replace(/\/[^\/]*$/, '');;
                        }

                        contentItem: RowLayout {
                            spacing: Kirigami.Units.smallSpacing

                            Kirigami.TitleSubtitle {
                                Layout.fillWidth: true
                                // Header: the folder
                                // 标题：文件夹名；副标题：路径
                                title: baseListItem.text
                                subtitle: baseListItem.subtitle
                            }

                            // 从轮播列表移除该文件夹
                            QQC2.ToolButton {
                                icon.name: "edit-delete-remove-symbolic"
                                text: i18nd("plasma_wallpaper_org.kde.image", "Remove Folder")
                                display: QQC2.Button.IconOnly
                                onClicked: imageWallpaper.removeSlidePath(baseListItem.modelData)

                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.text: text
                                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                            }

                            // 在文件管理器中打开该文件夹
                            QQC2.ToolButton {
                                icon.name: "document-open-folder"
                                text: i18nd("plasma_wallpaper_org.kde.image", "Open Folder…")
                                display: QQC2.Button.IconOnly
                                onClicked: Qt.openUrlExternally(baseListItem.modelData)

                                QQC2.ToolTip.visible: hovered
                                QQC2.ToolTip.text: text
                                QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                            }
                        }
                    }

                    // 未配置任何文件夹时显示空态提示
                    Kirigami.PlaceholderMessage {
                        anchors.centerIn: parent
                        width: parent.width - (Kirigami.Units.largeSpacing * 4)
                        visible: slidePathsView.count === 0
                        text: i18nd("plasma_wallpaper_org.kde.image", "There are no wallpaper locations configured")
                    }
                }
            }
        }

        Kirigami.Separator {
            Layout.fillHeight: true
        }

        // —— 右栏：懒加载缩略图网格组件 ——
        Loader {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // 动态加载 ThumbnailsComponent，并传入屏幕尺寸供计算缩略图大小
            Component.onCompleted: () => {
                this.setSource("ThumbnailsComponent.qml", {"screenSize": slideshowComponent.screenSize});
            }
        }
    }
}
