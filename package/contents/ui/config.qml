/*
    SPDX-FileCopyrightText: 2013 Marco Martin <mart@kde.org>
    SPDX-FileCopyrightText: 2014 Kai Uwe Broulik <kde@privat.broulik.de>
    SPDX-FileCopyrightText: 2019 David Redondo <kde@david-redondo.de>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QtControls2
import QtQuick.Layouts
import org.kde.plasma.wallpapers.image as PlasmaWallpaper
import org.kde.kquickcontrols as KQuickControls
import org.kde.kquickcontrolsaddons
import org.kde.newstuff as NewStuff
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import org.kde.config as KConfig

/**
 * 壁纸“配置”页主界面（在系统设置 / 桌面壁纸右键菜单中打开）。
 *
 * 顶部：图片定位方式、动态壁纸切换方式、背景（模糊 / 纯色）；
 * 中下部：根据当前壁纸类型加载对应面板——
 *   单图模式（org.kde.image）→ ThumbnailsComponent 图片网格；
 *   HTML/幻灯片模式（com.github.Moon-Haze.htmlwallpaper）→ SlideshowComponent。
 * 所有 cfg_* 属性与 KConfig 绑定（由 KCM 框架自动读写配置项），
 * 下方 DropArea 支持直接把图片 / 文件夹拖进配置窗口添加。
 *
 * For proper alignment, an ancestor **MUST** have id "appearanceRoot" and property "parentLayout"
 */
ColumnLayout {
    id: root

    // 由外层注入的环境对象
    property var configDialog
    property var wallpaperConfiguration: wallpaper.configuration
    property var parentLayout
    property var screenSize: Qt.size(Screen.width, Screen.height)

    // —— KConfig 绑定的配置项（cfg_* 为当前值，cfg_*Default 为默认值，用于高亮）——
    property alias cfg_Color: colorButton.color          // 背景纯色
    property color cfg_ColorDefault
    property string cfg_Image                            // 当前选中的单张壁纸
    property string cfg_ImageDefault
    property int cfg_FillMode                            // 图片定位方式（Image.FillMode）
    property int cfg_FillModeDefault
    property int cfg_SlideshowMode                       // 轮播排序方式
    property int cfg_SlideshowModeDefault
    property bool cfg_SlideshowFoldersFirst              // 按文件夹分组轮播
    property bool cfg_SlideshowFoldersFirstDefault: false
    property alias cfg_Blur: blurRadioButton.checked     // 背景模糊开关
    property bool cfg_BlurDefault
    property list<string> cfg_SlidePaths: []             // 轮播文件夹路径列表
    property list<string> cfg_SlidePathsDefault: []
    property int cfg_SlideInterval: 0                    // 轮播切换间隔（秒）
    property int cfg_SlideIntervalDefault: 0
    property list<string> cfg_UncheckedSlides: []        // 被用户取消勾选的幻灯片
    property list<string> cfg_UncheckedSlidesDefault: []
    property int cfg_DynamicMode: 0                      // 动态壁纸切换方式
    property int cfg_DynamicModeDefault: 0
    property bool cfg_ForceImageAnimation: false         // 强制动态图播放
    property bool cfg_ForceImageAnimationDefault: false

    // 任一配置项被界面改动后发出，通知外层（如预览、配置写入）刷新
    signal configurationChanged()
    /**
     * Emitted when the user finishes adding images using the file dialog.
     */
    // 用户在文件对话框中添加完图片后发出
    signal wallpaperBrowseCompleted();

    // 屏幕尺寸变化时同步给下方缩略图面板
    onScreenSizeChanged: function() {
        if (thumbnailsLoader.item) {
            thumbnailsLoader.item.screenSize = root.screenSize;
        }
    }

    // 保存配置：把用户新增/删除的壁纸固化到模型，并清除内部预览标记
    function saveConfig() {
        if (configDialog.currentWallpaper === "org.kde.image") {
            imageWallpaper.wallpaperModel.commitAddition();
            imageWallpaper.wallpaperModel.commitDeletion();
        }
        wallpaperConfiguration.PreviewImage = "null"; // internal, no need to save to file
    }

    // 弹出“添加图片 / 添加文件夹”对话框（组件用完即销毁）
    function openChooserDialog() {
        const dialogComponent = Qt.createComponent("AddFileDialog.qml");
        dialogComponent.createObject(root);
        dialogComponent.destroy();
    }

    // 选中一张壁纸：把（路径 + 选择器）拼成壁纸 URL 写入配置并生成预览
    function selectWallpaper(wallpaper: string, selectors: list<string>): void {
        cfg_Image = imageWallpaper.makeWallpaperUrl(wallpaper, selectors);
        wallpaperConfiguration.PreviewImage = cfg_Image;
    }

    // 切换动态壁纸模式；单图模式下还需把当前选中的壁纸重新应用一遍
    function selectDynamicMode(mode: /*PlasmaWallpaper.DynamicMode*/ int): void {
        cfg_DynamicMode = mode;

        if (root.configDialog.currentWallpaper === "org.kde.image") {
            selectWallpaper(thumbnailsLoader.item.view.currentItem.key,
                            thumbnailsLoader.item.view.currentItem.selectors);
        }
    }

    // ImageBackend：KDE 提供的图片壁纸后端，负责扫描目录、解析壁纸 URL、管理幻灯片
    PlasmaWallpaper.ImageBackend {
        id: imageWallpaper
        // 单图模式用 SingleImage，幻灯片 / HTML 模式用 SlideShow
        renderingMode: (root.configDialog.currentWallpaper === "org.kde.image") ? PlasmaWallpaper.ImageBackend.SingleImage : PlasmaWallpaper.ImageBackend.SlideShow
        targetSize: {
            // Lock screen configuration case
            // 锁屏配置场景下也要按物理像素计算
            return Qt.size(root.screenSize.width * Screen.devicePixelRatio, root.screenSize.height * Screen.devicePixelRatio)
        }
        dynamicMode: root.cfg_DynamicMode
        // 后端状态变化 → 回写配置属性，保证界面显示与后端一致
        onSlidePathsChanged: root.cfg_SlidePaths = slidePaths
        onUncheckedSlidesChanged: root.cfg_UncheckedSlides = uncheckedSlides
        onSlideshowModeChanged: root.cfg_SlideshowMode = slideshowMode
        onSlideshowFoldersFirstChanged: root.cfg_SlideshowFoldersFirst = slideshowFoldersFirst

        // 后端设置变化时通知配置面板刷新
        onSettingsChanged: root.configurationChanged()
    }

    // 配置变化 → 反向同步到后端控件（下拉框 / 后端属性）
    onCfg_FillModeChanged: {
        resizeComboBox.setMethod()
    }

    onCfg_SlidePathsChanged: {
        if (cfg_SlidePaths)
            imageWallpaper.slidePaths = cfg_SlidePaths
    }
    onCfg_UncheckedSlidesChanged: {
        if (cfg_UncheckedSlides)
            imageWallpaper.uncheckedSlides = cfg_UncheckedSlides
    }

    onCfg_SlideshowModeChanged: {
        if (cfg_SlideshowMode)
            imageWallpaper.slideshowMode = cfg_SlideshowMode
    }

    onCfg_SlideshowFoldersFirstChanged: {
        if (cfg_SlideshowFoldersFirst)
            imageWallpaper.slideshowFoldersFirst = cfg_SlideshowFoldersFirst
    }

    // HTMLWallpaper 模式下，把配置的 Image 直接绑定为当前页面地址。
    // 桌面对话框随选中变化实时更新；KCM 中固定不变。
    // 用绑定避免仅因选中当前壁纸而把配置误标为脏。
    Binding on cfg_Image {
        // in the desktop dialog, the config property is updated as Images change;
        // in the kcm, it's fixed. Bind it to make sure it's not marking the config
        // as dirty if the only change is the currently selected wallpaper.
        when: root.configDialog.currentWallpaper === "com.github.Moon-Haze.htmlwallpaper"
        value: root.wallpaperConfiguration.Image
    }

    spacing: 0

    // —— 顶部设置表单 ——
    Kirigami.FormLayout {
        id: formLayout

        // 单图模式下给底部网格留更多空间
        Layout.bottomMargin: root.configDialog.currentWallpaper === "org.kde.image" ? Kirigami.Units.largeSpacing : 0

        // 与上层“外观”页对齐表单标签列
        Component.onCompleted: function() {
            if (typeof appearanceRoot !== "undefined") {
                twinFormLayouts.push(appearanceRoot.parentLayout);
            }
        }

        // “定位方式”：缩放裁切 / 拉伸 / 保持比例 / 居中
        QtControls2.ComboBox {
            id: resizeComboBox
            Kirigami.FormData.label: i18ndc("plasma_wallpaper_org.kde.image", "@label:listbox", "Positioning:")
            model: [
                        {
                            'label': i18ndc("plasma_wallpaper_org.kde.image", "@item:inlistbox", "Scaled and cropped"),
                            'fillMode': Image.PreserveAspectCrop
                        },
                        {
                            'label': i18ndc("plasma_wallpaper_org.kde.image", "@item:inlistbox", "Scaled"),
                            'fillMode': Image.Stretch
                        },
                        {
                            'label': i18ndc("plasma_wallpaper_org.kde.image", "@item:inlistbox", "Scaled, keep proportions"),
                            'fillMode': Image.PreserveAspectFit
                        },
                        {
                            'label': i18ndc("plasma_wallpaper_org.kde.image", "@item:inlistbox", "Centered"),
                            'fillMode': Image.Pad
                        },
            ]

            textRole: "label"
            // 用户选择后写入填充模式配置
            onActivated: root.cfg_FillMode = model[currentIndex]["fillMode"]
            Component.onCompleted: setMethod();

            KCM.SettingHighlighter {
                highlight: root.cfg_FillModeDefault != root.cfg_FillMode
            }

            // 根据当前配置选中对应项
            function setMethod() {
                for (var i = 0; i < model.length; i++) {
                    if (model[i]["fillMode"] === root.cfg_FillMode) {
                        resizeComboBox.currentIndex = i;
                        break;
                    }
                }
            }
        }

        QtControls2.ButtonGroup { id: dayNightModeGroup }

        // —— 动态壁纸切换方式（自动 / 日夜循环 / 恒亮 / 恒暗）——
        RowLayout {
            spacing: Kirigami.Units.smallSpacing
            Kirigami.FormData.label: i18ndc("plasma_wallpaper_org.kde.image", "@label:listbox part of a sentence: 'Switch dynamic wallpapers [based on]'", "Switch dynamic wallpapers:")

            QtControls2.ComboBox {
                valueRole: "dynamicMode"
                textRole: "text"
                model: [
                    {
                        dynamicMode: PlasmaWallpaper.DynamicMode.Automatic,
                        text: i18ndc("plasma_wallpaper_org.kde.image", "@item:inlistbox part of a sentence: 'Switch dynamic wallpapers'", "Based on whether the Plasma style is light or dark ")},
                    {
                        dynamicMode: PlasmaWallpaper.DynamicMode.DayNight, text: i18ndc("plasma_wallpaper_org.kde.image", "@item:inlistbox part of a sentence: 'Switch dynamic wallpapers'", "Based on the day-night cycle")
                    },
                    {
                        dynamicMode: PlasmaWallpaper.DynamicMode.AlwaysLight,
                        text: i18ndc("plasma_wallpaper_org.kde.image", "@item:inlistbox", "Always use light variant")
                    },
                    {
                        dynamicMode: PlasmaWallpaper.DynamicMode.AlwaysDark,
                        text: i18ndc("plasma_wallpaper_org.kde.image", "@item:inlistbox", "Always use dark variant")
                    }
                ]
                // 用户选择后更新动态模式（必要时重新应用壁纸）
                onActivated: root.selectDynamicMode(currentValue)
                Component.onCompleted: currentIndex = indexOfValue(root.cfg_DynamicMode)

                KCM.SettingHighlighter {
                    highlight: root.cfg_DynamicModeDefault !== root.cfg_DynamicMode
                }
            }

            // “日夜循环”模式下的“配置…”按钮：打开日夜时间设置模块
            QtControls2.Button {
                visible: root.cfg_DynamicMode == 1
                enabled: KConfig.KAuthorized.authorizeControlModule("kcm_nighttime")
                text: i18ndc("plasma_wallpaper_org.kde.image", "@action:button Configure day-night cycle times", "Configure…")
                icon.name: "configure"
                onClicked: KCM.KCMLauncher.open("kcm_nighttime")
            }
        }

        QtControls2.ButtonGroup { id: backgroundGroup }

        // —— 背景样式：模糊 或 纯色（仅图片留白时才显示）——
        QtControls2.RadioButton {
            id: blurRadioButton
            // 仅 FillMode 为“保持比例 / 居中”时才会露出背景区
            visible: root.cfg_FillMode === Image.PreserveAspectFit || root.cfg_FillMode === Image.Pad
            Kirigami.FormData.label: i18nd("plasma_wallpaper_org.kde.image", "Background:")
            text: i18nd("plasma_wallpaper_org.kde.image", "Blur")
            QtControls2.ButtonGroup.group: backgroundGroup
        }

        RowLayout {
            id: colorRow
            visible: root.cfg_FillMode === Image.PreserveAspectFit || root.cfg_FillMode === Image.Pad
            // 纯色背景单选 + 取色按钮
            QtControls2.RadioButton {
                id: colorRadioButton
                text: i18nd("plasma_wallpaper_org.kde.image", "Solid color")
                checked: !root.cfg_Blur
                QtControls2.ButtonGroup.group: backgroundGroup

                KCM.SettingHighlighter {
                    highlight: root.cfg_Blur != root.cfg_BlurDefault
                }
            }
            KQuickControls.ColorButton {
                id: colorButton
                color: root.cfg_Color
                dialogTitle: i18nd("plasma_wallpaper_org.kde.image", "Select Background Color")

                KCM.SettingHighlighter {
                    highlight: root.cfg_Color != root.cfg_ColorDefault
                }
            }
        }
    }

    // —— 主内容区：接受拖放，并按壁纸类型加载对应面板 ——
    DropArea {
        Layout.fillWidth: true
        Layout.fillHeight: true

        // 拖动进入：携带 URL（图片 / 文件夹）时允许投放
        onEntered: drag => {
            if (drag.hasUrls) {
                drag.accept();
            }
        }
        // 放下：按当前模式添加为图片或轮播路径
        onDropped: drop => {
            drop.urls.forEach(function (url) {
                if (root.configDialog.currentWallpaper === "org.kde.image") {
                    imageWallpaper.addUsersWallpaper(url);
                } else {
                    imageWallpaper.addSlidePath(url);
                }
            });
            // Scroll to top to view added images
            // 添加完成后滚动到顶部展示新图片
            if (root.configDialog.currentWallpaper === "org.kde.image") {
                thumbnailsLoader.item.view.positionViewAtIndex(0, GridView.Beginning);
            }
        }

        // 按壁纸类型懒加载：单图 → Thumbnails；HTML/幻灯片 → Slideshow
        Loader {
            id: thumbnailsLoader
            anchors.fill: parent

            function loadWallpaper () {
                let source = (root.configDialog.currentWallpaper == "org.kde.image") ? "ThumbnailsComponent.qml" :
                    ((root.configDialog.currentWallpaper == "com.github.Moon-Haze.htmlwallpaper") ? "SlideshowComponent.qml" : "");

                let props = {screenSize: root.screenSize};

                // 幻灯片面板需要访问壁纸配置对象
                if (root.configDialog.currentWallpaper == "com.github.Moon-Haze.htmlwallpaper") {
                    props["configuration"] = root.wallpaperConfiguration;
                }
                thumbnailsLoader.setSource(source, props);
            }
        }

        // 壁纸类型切换时重新加载对应面板
        Connections {
            target: root.configDialog
            function onCurrentWallpaperChanged() {
                thumbnailsLoader.loadWallpaper();
            }
        }

        // 初次加载
        Component.onCompleted: () => {
            thumbnailsLoader.loadWallpaper();
        }

    }

    // 关闭配置页时清理内部预览标记
    Component.onDestruction: {
        if (wallpaperConfiguration)
            wallpaperConfiguration.PreviewImage = "null";
    }
}
