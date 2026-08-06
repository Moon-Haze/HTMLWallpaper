import QtQuick
import QtQuick.Controls
import QtWebEngine

import org.kde.plasma.plasmoid

WallpaperItem {
    id: wallpaper

    property bool loadFailed: false
    property string loadErrorString: ""

    // 支持拖放：把本地 .html 文件拖到桌面，直接设为壁纸
    onOpenUrlRequested: (url) => {
        wallpaper.configuration.DisplayPage = url;
        wallpaper.configuration.writeConfig();
    }

    WebEngineView {
        id: webView
        anchors.fill: parent
        // 多屏幕共享同一个 profile，复用缓存/UA/Cookie
        profile: ProfileProvider.sharedProfile
        url: wallpaper.configuration.DisplayPage
        zoomFactor: wallpaper.configuration.ZoomFactor
        backgroundColor: "black"
        onCertificateError: function (error) {
            if (wallpaper.configuration.InsecureHTTPS) {
                error.acceptCertificate()
            } else {
                error.rejectCertificate()
            }
        }
        settings.playbackRequiresUserGesture: false
        onLoadingChanged: function (loadRequest) {
            if (loadRequest.status === WebEngineView.LoadFailedStatus) {
                wallpaper.loadFailed = true
                wallpaper.loadErrorString = loadRequest.errorString
            } else if (loadRequest.status === WebEngineView.LoadSucceededStatus) {
                wallpaper.loadFailed = false
            }
        }
    }

    // 页面加载失败时的提示层
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
