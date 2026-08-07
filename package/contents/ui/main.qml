import QtQuick
import QtQuick.Controls
import QtWebEngine

import org.kde.plasma.plasmoid

/**
 * HTMLWallpaper 壁纸插件主入口。
 *
 * 本文件是 KDE Plasma 壁纸包（Plasma Wallpaper Package）的根 QML 组件，
 * 由 plasmashell 在每次应用壁纸时实例化一个 WallpaperItem。
 * 核心职责：用 QtWebEngine（WebEngineView）渲染用户配置的本地 / 远程 HTML
 * 页面，并把它铺满整个桌面作为壁纸；同时处理证书、加载失败等边界情况。
 */
WallpaperItem {
    id: wallpaper

    // 页面加载失败标志与错误信息，供下方的错误提示层使用
    property bool loadFailed: false
    property string loadErrorString: ""

    // 支持拖放：把本地 .html 文件拖到桌面，直接设为壁纸
    onOpenUrlRequested: (url) => {
        wallpaper.configuration.DisplayPage = url;
        wallpaper.configuration.writeConfig();
    }

    // 承载壁纸 HTML 页面的 WebEngine 视图
    WebEngineView {
        id: webView
        anchors.fill: parent
        // 多屏幕共享同一个 profile，复用缓存/UA/Cookie
        profile: ProfileProvider.sharedProfile
        // 加载用户配置的页面地址（可为本地 file:// 或远程 https://）
        url: wallpaper.configuration.DisplayPage
        // 缩放因子，对应配置项中的 ZoomFactor
        zoomFactor: wallpaper.configuration.ZoomFactor
        // 页面渲染前先铺黑底，避免闪烁 / 出现白屏
        backgroundColor: "black"
        // 处理自签名等不受信任的 HTTPS 证书：
        // 开启 InsecureHTTPS 配置时接受证书，否则拒绝
        onCertificateError: function (error) {
            if (wallpaper.configuration.InsecureHTTPS) {
                error.acceptCertificate()
            } else {
                error.rejectCertificate()
            }
        }
        // 允许页面内媒体（如视频）自动播放，无需用户手势
        settings.playbackRequiresUserGesture: false
        // 监听页面加载状态：失败时记录错误信息，成功后清除失败标志
        onLoadingChanged: function (loadRequest) {
            if (loadRequest.status === WebEngineView.LoadFailedStatus) {
                wallpaper.loadFailed = true
                wallpaper.loadErrorString = loadRequest.errorString
            } else if (loadRequest.status === WebEngineView.LoadSucceededStatus) {
                wallpaper.loadFailed = false
            }
        }
    }

    // 页面加载失败时的提示层，覆盖在 WebEngineView 之上（z:1）
    Rectangle {
        anchors.fill: parent
        visible: wallpaper.loadFailed
        color: "black"
        z: 1

        Label {
            anchors.centerIn: parent
            width: parent.width * 0.8
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: "white"
            text: i18nd("plasma_wallpaper_com.github.Moon-Haze.htmlwallpaper",
                        "无法加载页面：\n%1\n\n请检查 URL 或网络连接。").arg(wallpaper.loadErrorString)
        }
    }
}
