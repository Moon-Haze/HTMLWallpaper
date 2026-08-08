/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import QtWebEngine

/**
 * HTML 壁纸实时预览面板（dev 程序右侧）。
 *
 * 复用 main.qml 的「混合参数注入」核心（不依赖 plasmashell 的 WallpaperItem）：
 *   - 初始加载：displayPage（纯入口）+ query 参数拼入 URL；
 *   - 运行中参数变化：runJavaScript 推 wallpaperPropertyListener
 *     .applyUserProperties(json)，页面实现了监听器则实时更新、不重载；
 *   - 页面无监听器：回退为带新参数重新加载整页。
 *
 * 由 DevShell 监听 config.qml 的 cfg_DisplayPage / cfg_WallpaperProperties
 * 变化并喂给本面板的 displayPage / propertiesJson。
 */
Item {
    id: panel

    // 入口 HTML（纯，不带 query）与参数 JSON
    property string displayPage: ""
    property string propertiesJson: "{}"
    // 已注入到页面的 JSON（避免重复注入 / 重复重载）
    property string _injectedJson: ""

    // 拼接带参数 query 的完整 URL（初始加载 / 无监听器回退重载时使用）
    function _pageUrl(): string {
        const base = panel.displayPage;
        if (!base) {
            return "";
        }
        const sep = base.indexOf("?") >= 0 ? "&" : "?";
        return base + sep + "wallpaperProperties=" + encodeURIComponent(panel.propertiesJson);
    }

    // 实时推送参数：页面有 wallpaperPropertyListener.applyUserProperties 则
    // 调用并标记已注入；否则回退为带新参数重新加载整页
    function _injectProperties(): void {
        const json = panel.propertiesJson;
        if (json === panel._injectedJson) {
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
            panel._injectedJson = json;
            if (!hasListener) {
                // 页面无监听器：带新参数重新加载（初始 query 也能被读取）
                panel._applyUrl();
            }
        });
    }

    // 设置页面 URL（初始加载 / displayPage 变化 / 回退重载共用）
    function _applyUrl(): void {
        const url = panel._pageUrl();
        if (url) {
            webView.url = url;
            panel._injectedJson = panel.propertiesJson;
        } else {
            // 尚未选中壁纸：空 URL 会触发警告，显式显示空白页
            webView.url = "about:blank";
            panel._injectedJson = "";
        }
    }

    // 入口页变化 → 整页加载；参数变化 → 实时注入（无监听器回退重载）
    onDisplayPageChanged: panel._applyUrl()
    onPropertiesJsonChanged: panel._injectProperties()

    WebEngineView {
        id: webView
        anchors.fill: parent
        // 不指定 profile，使用 QtWebEngine 默认 profile
        // url 由 _applyUrl() 赋值，不直接绑定
        backgroundColor: "black"
        // 页面加载成功后再补一次注入（兼容首次未带 query、或页面内重载）
        onLoadingChanged: function (loadRequest) {
            if (loadRequest.status === WebEngineView.LoadSucceededStatus) {
                panel._injectProperties();
            }
        }
    }

    Component.onCompleted: panel._applyUrl()
}
