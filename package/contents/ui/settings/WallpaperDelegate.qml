/*
    SPDX-FileCopyrightText: 2013 Marco Martin <mart@kde.org>
    SPDX-FileCopyrightText: 2014 Sebastian Kügler <sebas@kde.org>
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QtControls2
import Qt5Compat.GraphicalEffects
import QtWebEngine

import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

/**
 * 网格中的单个壁纸缩略图项。
 *
 * 展示预览图（可带模糊背景），支持点击应用壁纸与单选参与轮播。
 * 左上角叠加单选按钮，当前勾选项为唯一轮播壁纸（互斥选择）。
 */
KCM.GridDelegate {
    id: wallpaperDelegate

    // 暴露给外层：背景色与预览采样尺寸
    property alias color: backgroundRect.color
    property alias previewSize: previewImage.sourceSize
    // 注入的解析器实例（点选应用时使用）
    property QtObject htmlWallpaper: null

    // 标记为"待删除"的项半透明显示（HTML 模式模型无此 role，恒为不透明）
    opacity: model.pendingDeletion ? 0.5 : 1
    scale: index, 1 // Workaround for https://bugreports.qt.io/browse/QTBUG-107458

    // 标题与副标题（HTML 模式用 description，缺省时回退 author）
    text: model.display
    subtitle: model.description !== undefined && model.description ? model.description : model.author

    hoverEnabled: true

    // —— 悬停 HTML 实时预览 ——
    // 测试/外部可注入的 WebEngine 组件(测试注入轻量假组件,避免 offscreen 渲染)
    property Component webViewComponentOverride: null
    // 预览是否激活(Loader 已实例化);测试与诊断用只读观察
    readonly property bool hoverPreviewActive: hoverPreview.item !== null
    // 当前预览 URL(测试断言用)
    readonly property string hoverPreviewUrl: hoverPreview.item ? hoverPreview.item.url : ""

    // 内联 WebEngineView:仅由 hoverPreview 加载时实例化。
    // 注意:Component 有独立作用域,不能引用外层委托的 id(会 ReferenceError),
    // 故加载成功/失败切换统一由委托级 Connections 处理。
    Component {
        id: webViewComponent
        WebEngineView {
            anchors.fill: parent
            backgroundColor: "black"
            visible: false // 加载成功前隐藏,图片保持可见
            // url 由 startHoverPreview() 在 Loader 创建后赋值
        }
    }

    // 悬停驱动统一入口(真实鼠标与测试共用;测试环境 offscreen 无法驱动只读的 hovered)
    function startHoverPreview() {
        hoverTimer.start();
    }
    function stopHoverPreview() {
        hoverTimer.stop();
        hoverPreview.sourceComponent = null; // 移开即销毁渲染实例,恢复 preview 图片
    }

    Timer {
        id: hoverTimer
        interval: 300 // 悬停防抖:快速滑过不触发
        onTriggered: {
            hoverPreview.sourceComponent = webViewComponentOverride ? webViewComponentOverride : webViewComponent;
            hoverPreview.item.url = model.source; // 入口 HTML,无参数(默认效果)
        }
    }

    onHoveredChanged: {
        if (hovered) {
            startHoverPreview();
        } else {
            stopHoverPreview();
        }
    }

    // —— 缩略图内容 ——
    thumbnail: Rectangle {
        id: backgroundRect
        anchors.fill: parent

        // 预览图未就绪时显示占位图标
        Kirigami.Icon {
            anchors.centerIn: parent
            width: Kirigami.Units.iconSizes.large
            height: width
            source: "view-preview"
            visible: previewImage.status != Image.Ready
        }

        FastBlur {
            id: fastBlur
            visible: cfg_Blur
            anchors.fill: parent
            radius: 4
            source: Image {
                asynchronous: true
                retainWhileLoading: true
                cache: false
                fillMode: Image.PreserveAspectCrop
                source: fastBlur.visible ? previewImage.source : ""
                sourceSize: previewImage.sourceSize
                visible: false
            }
        }

        Image {
            id: previewImage
            anchors.fill: parent
            asynchronous: true
            retainWhileLoading: true
            cache: false
            source: model.preview
        }

        // 悬停 HTML 实时预览:覆盖在 previewImage 之上,默认不加载(零 WebEngine 资源)
        Loader {
            id: hoverPreview
            anchors.fill: parent
            z: 1
        }

        Behavior on color {
            ColorAnimation {
                duration: Kirigami.Units.longDuration
                easing.type: Easing.InOutQuad
            }
        }
    }

    Behavior on opacity {
        NumberAnimation {
            duration: Kirigami.Units.longDuration
            easing.type: Easing.InOutQuad
        }
    }

    // 委托级监听 WebEngine 加载状态:item 为 null 时自动停用,item 创建后自动生效
    Connections {
        target: hoverPreview.item
        function onLoadingChanged(loadRequest) {
            if (loadRequest.status === WebEngineView.LoadSucceededStatus) {
                hoverPreview.item.visible = true; // 覆盖 preview 图片,不闪黑
            } else if (loadRequest.status === WebEngineView.LoadFailedStatus) {
                stopHoverPreview(); // 加载失败:销毁实例,回退 preview 图片
            }
        }
    }

    // 点击行为：解析并应用该壁纸（参数经 wallpaperParsed 写配置）；
    // 无路径时仅切换勾选状态
    onClicked: {
        if (htmlWallpaper && model.path) {
            htmlWallpaper.parseWallpaper(model.path);
            root.cfg_DisplayPage = model.source;
        } else {
            // 无路径项（如“添加”占位）点击时翻转勾选，同样走互斥写回
            if (htmlWallpaper && htmlWallpaper.wallpapers) {
                htmlWallpaper.wallpapers.setExclusiveChecked(index, !model.checked)
            }
        }
        // 注意：不再手动改 GridView.currentIndex，以免销毁 cfg_DisplayPage 驱动的绑定，
        // 高亮由 resetCurrentIndex() 建立的绑定自动跟随 cfg_DisplayPage
    }
}
