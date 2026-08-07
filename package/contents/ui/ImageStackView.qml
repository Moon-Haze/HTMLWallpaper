/*
    SPDX-FileCopyrightText: 2013 Marco Martin <mart@kde.org>
    SPDX-FileCopyrightText: 2014 Sebastian Kügler <sebas@kde.org>
    SPDX-FileCopyrightText: 2014 Kai Uwe Broulik <kde@privat.broulik.de>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import org.kde.plasma.wallpapers.image as Wallpaper
import org.kde.kirigami as Kirigami

/**
 * 图片栈视图：壁纸媒体的统一渲染入口。
 *
 * 用 StackView 管理“当前正在显示的媒体组件”，并根据 MediaProxy 报告的背景类型
 * （静态图 / 动态图 / 日夜图）动态加载对应的 mediacomponent/ 子组件。
 * 来源变化（换壁纸、改颜色、开模糊等）时通过 loadImage() 重新创建媒体项，
 * 并用淡入过渡平滑替换旧项。
 */
QQC2.StackView {
    id: view

    // —— 由外层 WallpaperItem 传入的渲染参数 ——
    required property int fillMode
    required property string configColor
    required property bool blur
    property alias source: mediaProxy.source
    required property size sourceSize
    required property /*WallpaperItem*/ QtObject wallpaperInterface // weaker type to support mock object in autotests

    // MediaProxy 负责把图片 URL 解析成可渲染的 modelImage
    readonly property alias mediaProxy: mediaProxy
    readonly property url modelImage: mediaProxy.modelImage
    // 动态图组件强制播放（即使窗口被遮挡也不暂停）
    property bool forceImageAnimation: false

    /**
     * Stores pending image here to avoid the default image overriding the true image.
     *
     * @see BUG 456189
     */
    // 暂存“正在加载的下一张图”，避免默认图覆盖真实图片（KDE BUG 456189）
    property Item pendingImage

    // 是否跳过切换过渡动画（首屏 / 强制加载时置 true）
    property bool doesSkipAnimation: true

    // 缓存已实例化的媒体组件，避免反复 createComponent
    property Component staticImageComponent
    property Component animatedImageComponent
    property Component dayNightComponent

    // 任一渲染参数变化时，延迟一帧再重新加载图片，避免高频抖动
    onFillModeChanged: Qt.callLater(loadImage);
    onModelImageChanged: Qt.callLater(loadImage);
    onConfigColorChanged: Qt.callLater(loadImage);
    onBlurChanged: Qt.callLater(loadImage);

    // 根据背景类型选择对应的媒体组件，未加载过则动态创建
    function createBackgroundComponent() {
        switch (mediaProxy.backgroundType) {
        case Wallpaper.BackgroundType.Image:
        case Wallpaper.BackgroundType.VectorImage: {
            // 静态位图 / 矢量图 → StaticImageComponent
            if (!staticImageComponent) {
                staticImageComponent = Qt.createComponent("mediacomponent/StaticImageComponent.qml");
            }
            return staticImageComponent;
        }
        case Wallpaper.BackgroundType.AnimatedImage: {
            // 动态图（GIF 等）→ AnimatedImageComponent
            if (!animatedImageComponent) {
                animatedImageComponent = Qt.createComponent("mediacomponent/AnimatedImageComponent.qml");
            }
            return animatedImageComponent;
        }
        case Wallpaper.BackgroundType.DayNight: {
            // 昼夜双图 → DayNightComponent
            if (!dayNightComponent) {
                dayNightComponent = Qt.createComponent("mediacomponent/DayNightComponent.qml");
            }
            return dayNightComponent;
        }
        }
    }

    // 立即重新加载图片（跳过动画），供 MediaProxy 状态变化时调用
    function loadImageImmediately() {
        loadImage(true);
    }

    // 核心加载流程：销毁旧待载项 → 创建新媒体项 → 等待其加载完成 → 替换进 StackView
    function loadImage(skipAnimation) {
        // 若上一张图还在加载中，先取消并销毁，避免竞态
        if (pendingImage) {
            pendingImage.statusChanged.disconnect(replaceWhenLoaded);
            pendingImage.destroy();
            pendingImage = null;
        }

        // 未知的后端类型：回退到默认单图
        if (mediaProxy.providerType == Wallpaper.Provider.Unknown) {
            console.error("The backend got an unknown wallpaper provider type. The wallpaper will now fall back to the default. Please check your wallpaper configuration!");
            mediaProxy.useSingleImageDefaults();
            return;
        }

        // 首屏或尺寸变化时跳过淡入动画
        doesSkipAnimation = view.currentItem == undefined || view.currentItem.sourceSize !== view.sourceSize || !!skipAnimation;
        const baseImage = createBackgroundComponent();
        const properties = {
            // Use mediaProxy instead of view because colorSchemeChanged needs immediately update the wallpaper
            // 传 mediaProxy 而非 view，保证主题配色变化时能立刻刷新壁纸
            "source": mediaProxy.modelImage,
            "fillMode": view.fillMode,
            "sourceSize": view.sourceSize,
            "color": view.configColor,
            "blur": view.blur,
            "parent": view,
            "implicitWidth": view.width,
            "implicitHeight": view.height,
            "visible": false, // 加载完成前先隐藏，避免闪出半成品
        };
        // Only pass forceImageAnimation for AnimatedImageComponent
        // forceImageAnimation 仅对动态图组件有意义，单独传入
        if (mediaProxy.backgroundType === Wallpaper.BackgroundType.AnimatedImage) {
            properties.forceImageAnimation = view.forceImageAnimation;
        }
        // 创建媒体项实例
        pendingImage = baseImage.createObject(view, properties);

        if (!pendingImage) {
            console.warn(baseImage.errorString());
            return;
        }

        // 等待其加载完成后再替换显示
        pendingImage.statusChanged.connect(replaceWhenLoaded);
        replaceWhenLoaded();
    }

    // 待加载项就绪后的回调：把新图替换进 StackView 并清理资源
    function replaceWhenLoaded() {
        // 仍在加载中则等待状态下次变化
        if (pendingImage.status === Image.Loading) {
            return;
        }

        pendingImage.statusChanged.disconnect(replaceWhenLoaded);
        // BUG 454908: Update accent color
        // 激活后同步强调色（accent color）到壁纸接口（KDE BUG 454908）
        pendingImage.QQC2.StackView.onActivated.connect(() => {
            if (Qt.colorEqual(mediaProxy.customColor, "transparent") && Qt.colorEqual(wallpaperInterface.accentColor, "transparent")) {
                wallpaperInterface.accentColorChanged();
            } else {
                wallpaperInterface.accentColor = mediaProxy.customColor;
            }
        });

        // onRemoved only fires when all transitions end. If a user switches wallpaper quickly this adds up
        // Given it's such a heavy item, try to cleanup as early as possible
        // 媒体项很重：在 deactivated 和 removed 时尽早销毁，避免快速切换壁纸时旧项堆积
        pendingImage.QQC2.StackView.onDeactivated.connect(pendingImage.destroy);
        pendingImage.QQC2.StackView.onRemoved.connect(pendingImage.destroy);
        // 用带过渡的 replace 淡入新图
        view.replace(pendingImage, {}, QQC2.StackView.Transition);

        // 通知外层壁纸加载结束
        wallpaperInterface.loading = false;

        // 若图片最终没加载成功，回退到默认单图
        if (pendingImage.status !== Image.Ready) {
            mediaProxy.useSingleImageDefaults();
        }

        pendingImage = null;
    }

    replaceEnter: Transition {
        NumberAnimation {
            id: replaceEnterOpacityAnimator
            property: "opacity"
            from: 0
            to: 1
            // The value is to keep compatible with the old feeling defined by "TransitionAnimationDuration" (default: 1000)
            duration: Math.round(Kirigami.Units.veryLongDuration * 2.5)
        }
        enabled: !view.doesSkipAnimation
    }
    // Keep the old image around till the new one is fully faded in
    // If we fade both at the same time you can see the background behind glimpse through
    // 旧图停留至新图完全淡入：两图同时淡出淡入会透出背后的底色
    replaceExit: Transition{
        PauseAnimation {
            // 500: The exit transition starts first and can be completed earlier than the enter transition
            // 退出动画晚 500ms 结束，确保旧图覆盖到新图淡入完成
            duration: replaceEnterOpacityAnimator.duration + 500
        }
    }

    // MediaProxy：把壁纸的 URL / 文件路径解析为可渲染图片，并跟踪实际尺寸
    Wallpaper.MediaProxy {
        id: mediaProxy

        // 按屏幕尺寸生成目标采样尺寸
        targetSize: view.sourceSize

        // 图片实际尺寸 / 配色方案 / 源文件变化时，立即刷新壁纸
        onActualSizeChanged: Qt.callLater(view.loadImageImmediately);
        onColorSchemeChanged: view.loadImageImmediately();
        onSourceFileUpdated: view.loadImageImmediately()
    }
}
