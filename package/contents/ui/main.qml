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
 *
 * 壁纸参数（WallpaperProperties JSON）采用**混合注入**：
 *   - 初始加载：SelectWallpaper（纯入口）+ query 参数拼入 URL（页面可读
 *     location.search 的 wallpaperProperties 字段）；
 *   - 运行中参数变化：`runJavaScript` 推送给页面的
 *     `wallpaperPropertyListener.applyUserProperties(json)`（Wallpaper Engine
 *     兼容接口），页面实现了监听器则实时更新、不重载；
 *   - 页面无监听器：回退为把新参数拼入 URL 重新加载整页（保证最终一致）。
 */
WallpaperItem {
    id: wallpaper

    // 页面加载失败标志与错误信息，供下方的错误提示层使用
    property bool loadFailed: false
    property string loadErrorString: ""

    // 入口页面（纯，不带 query）与参数 JSON，取自配置；与 url 分离以便
    // 参数变化时用 JS 注入而非整页重载
    property string _displayPage: ""
    property string _propertiesJson: "{}"
    // 已注入到页面的 JSON（避免重复注入 / 重复重载）
    property string _injectedJson: ""

    // 拼接带参数 query 的完整 URL（初始加载 / 无监听器回退重载时使用）
    function _pageUrl(): string {
        const base = wallpaper._displayPage;
        if (!base) {
            return "";
        }
        const sep = base.indexOf("?") >= 0 ? "&" : "?";
        return base + sep + "wallpaperProperties=" + encodeURIComponent(wallpaper._propertiesJson);
    }

    // 实时推送参数：页面有 wallpaperPropertyListener.applyUserProperties 则
    // 调用并标记已注入；否则回退为带新参数重新加载整页
    function _injectProperties(): void {
        const json = wallpaper._propertiesJson;
        if (json === wallpaper._injectedJson) {
            return;
        }
        const script = "(function(){"
            + "if (window.wallpaperPropertyListener && window.wallpaperPropertyListener.applyUserProperties) {"
            + "  window.wallpaperPropertyListener.applyUserProperties(" + json + ");"
            + "  return true;"
            + "}"
            + "return false;"
            + "})()";
        webView.runJavaScript(script, function (hasListener) {
            wallpaper._injectedJson = json;
            if (!hasListener) {
                // 页面无监听器：带新参数重新加载（初始 query 也能被读取）
                wallpaper._applyUrl();
            }
        });
    }

    // 设置页面 URL（初始加载 / SelectWallpaper 变化 / 回退重载共用）
    function _applyUrl(): void {
        webView.url = wallpaper._pageUrl();
        wallpaper._injectedJson = wallpaper._propertiesJson;
    }

    // 支持拖放：把本地 .html 文件拖到桌面，直接设为壁纸
    onOpenUrlRequested: (url) => {
        wallpaper.configuration.SelectWallpaper = url;
        wallpaper.configuration.writeConfig();
        wallpaper._displayPage = String(url);
        wallpaper._applyUrl();
    }

    // 监听配置变化：入口页变化 → 重新加载；参数变化 → 实时注入（无监听器回退重载）
    Connections {
        target: wallpaper.configuration
        function onValueChanged(key: string) {
            if (key === "SelectWallpaper") {
                wallpaper._displayPage = wallpaper.configuration.SelectWallpaper || "";
                wallpaper._applyUrl();
            } else if (key === "WallpaperProperties") {
                wallpaper._propertiesJson = wallpaper.configuration.WallpaperProperties || "{}";
                wallpaper._injectProperties();
            }
        }
    }

    // 承载壁纸 HTML 页面的 WebEngine 视图
    WebEngineView {
        id: webView
        anchors.fill: parent
        // 不指定 profile，使用 QtWebEngine 默认 profile
        // url 由 _applyUrl() 赋值（SelectWallpaper + 参数 query），不直接绑定
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
        // 监听页面加载状态：失败时记录错误信息，成功后清除失败标志并注入参数
        onLoadingChanged: function (loadRequest) {
            if (loadRequest.status === WebEngineView.LoadSucceededStatus) {
                wallpaper.loadFailed = false
                // 页面就绪后注入参数（初始 query 已含；这里兼容首次加载未带
                // query 的情况，并保证页面无监听器时也能拿到最新参数）
                wallpaper._injectProperties()
            } else if (loadRequest.status === WebEngineView.LoadFailedStatus) {
                wallpaper.loadFailed = true
                wallpaper.loadErrorString = loadRequest.errorString
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
            text: i18nd("plasma_wallpaper_com.github.moon_haze.htmlwallpaper",
                        "无法加载页面：\n%1\n\n请检查 URL 或网络连接。").arg(wallpaper.loadErrorString)
        }
    }

    // 首次加载：从配置取入口 + 参数，拼 query 后显示
    Component.onCompleted: {
        wallpaper._displayPage = wallpaper.configuration.SelectWallpaper || "";
        wallpaper._propertiesJson = wallpaper.configuration.WallpaperProperties || "{}";
        wallpaper._applyUrl();
    }
}
