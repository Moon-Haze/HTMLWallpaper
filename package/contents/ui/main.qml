
import QtQuick
import QtWebEngine

import org.kde.plasma.plasmoid

WallpaperItem {
    WebEngineView{
        anchors.fill: parent
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
    }
}
