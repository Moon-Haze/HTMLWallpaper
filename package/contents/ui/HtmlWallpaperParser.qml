/*
    SPDX-FileCopyrightText: 2026 Moon-Haze <swx1126200515@outlook.com>

    SPDX-License-Identifier: GPL-2.0-or-later
*/

import QtQuick
import Qt.labs.folderlistmodel

/**
 * HtmlWallpaperParser：解析“html-wallpapers”格式的 HTML 壁纸。
 *
 * 目录约定（Wallpaper Engine 风格，样例见 pkg/wallpapers/src/*）：
 *
 *     <根目录>/<壁纸名>/
 *         ├── project.json   —— 元数据 + 可配置属性（本对象解析的核心）
 *         ├── index.html     —— 壁纸入口页面（project.json 的 "file" 字段可覆盖）
 *         └── preview.*      —— 预览图（"preview" 字段相对路径）
 *
 * project.json 关键字段：
 *   - title / description / tags / type / visibility / workshopid
 *   - file      入口 HTML 文件名，缺省 "index.html"
 *   - preview   预览图相对路径（缺省时 preview 为空，调用方自行显示占位）
 *   - general.properties   可配置属性表：每个键名就是注入到页面的变量名。
 *        属性支持的 type：color | slider | combo | bool | file | textinput | text | group
 *        通用字段：text（显示标签，允许含 HTML）、order（排序）、condition（JS 条件表达式）
 *        slider：value / min / max / step / fraction / precision
 *        combo：options = [ { label, value }, ... ]  +  value
 *        color：value 为 "R G B" 三值，各 0~1（空格分隔），见 colorToHex()
 *
 * 典型用法：
 *   HtmlWallpaperParser { id: parser }        // 或 Component 化后动态加载
 *   parser.scan();                            // 扫描 rootPaths → wallpapers 模型
 *   parser.parseWallpaper(selectedPath)       // 解析单壁纸 → currentWallpaper / currentProperties
 *
 * 需要把解析出的属性注入页面时（如拼接 query string）：
 *   parser.parseWallpaper(dir); ...
 *   webView.url = parser.applyPropertiesToUrl(parser.currentWallpaper.entry);
 */
QtObject {
    id: parser

    // —— 扫描配置 ——
    // 待扫描的壁纸根目录（可多个）。默认匹配 main.xml 中 SlidePaths 的默认值。
    property list<url> rootPaths: ["file:///usr/share/html-wallpapers"]
    // 只收录 type 字段包含 "web" 的壁纸（大小写不敏感）；type 缺失时按 web 处理。
    // 置 false 则收录目录下所有含 project.json 的子目录。
    property bool requireWebType: true

    // 扫描是否进行中（避免重复触发 scan()）
    readonly property bool scanInProgress: dirLister.status === FolderListModel.Loading || _pending > 0

    // —— 扫描结果：壁纸列表模型，可直接作为 GridView/ListView 的 model ——
    // 每项字段：name（目录名）、title、description、tags(string[])、type、
    //           visibility、workshopid、path(目录 url)、entry(入口 html url)、preview(预览图 url)
    readonly property ListModel wallpapers: ListModel {
        id: wallpapersModel
    }

    // —— 最近一次 parseWallpaper() 的解析结果 ——
    // 元数据对象（字段同 wallpapers 每项）；尚未解析时为 null
    property var currentWallpaper: null
    // 当前壁纸的可配置属性模型（由 general.properties 解析而来，按 order 排序）
    // 每项字段：key、type、text、value、min、max、step、fraction、precision、
    //           options(数组)、condition、group、order
    readonly property ListModel currentProperties: ListModel {
        id: propertiesModel
    }

    // 扫描全部完成（可能部分子目录解析失败，已在日志警告）
    signal scanFinished()
    // 解析单个壁纸完成；参数为元数据对象
    signal wallpaperParsed(var metadata)
    // 某个根目录无法读取时发出（path：根目录 url，error：底层错误字符串）
    signal scanFailed(var path, string error)

    // 枚举目录用（QtObject 内可放置非可视项）。目录扫描完成后 folder 由 scanPath() 逐根赋值。
    FolderListModel {
        id: dirLister
        showDirs: true          // 只需子目录
        showFiles: false
        showDotAndDotDot: false
        sortField: FolderListModel.Name
    }

    // 等待 FolderListModel 异步填充完成（Loading → Ready / 失败）
    function _waitFolderReady(cb) {
        if (dirLister.status !== FolderListModel.Loading) {
            cb();
        } else {
            Qt.callLater(function () {
                _waitFolderReady(cb);
            });
        }
    }

    // —— 扫描入口：顺序扫描 rootPaths，把各根下的合法壁纸填入 wallpapers ——
    function scan() {
        if (scanInProgress) {
            return;
        }
        wallpapersModel.clear();
        _scanPath(0);
    }

    function _scanPath(index) {
        if (index >= rootPaths.length) {
            scanFinished();
            return;
        }
        const base = _toUrl(rootPaths[index]);
        dirLister.folder = base;
        _waitFolderReady(function () {
            if (dirLister.status !== FolderListModel.Ready) {
                console.warn("HtmlWallpaperParser: cannot list directory " + base
                             + (dirLister.errorString ? ": " + dirLister.errorString : ""));
                scanFailed(base, dirLister.errorString || "");
            } else {
                _collectWallpapers(function () {
                    _scanPath(index + 1);
                });
            }
        });
    }

    // 读取当前 dirLister 下列出的每个子目录的 project.json，命中则追加进模型
    function _collectWallpapers(done) {
        let dirs = [];
        for (let i = 0; i < dirLister.count; i++) {
            const entry = dirLister.get(i);
            if (entry.fileIsDir) {
                dirs.push(entry.fileURL);
            }
        }
        if (dirs.length === 0) {
            done();
            return;
        }

        let pending = dirs.length;
        dirs.forEach(function (dirUrl) {
            _loadProjectJson(dirUrl, function (data, url) {
                const meta = data ? _parseMetadata(url, data) : null;
                if (meta) {
                    wallpapersModel.append(meta);
                }
                if (--pending === 0) {
                    done();
                }
            });
        });
    }

    // —— 解析单个壁纸目录：填充 currentWallpaper / currentProperties ——
    function parseWallpaper(path) {
        const dirUrl = _toUrl(path);
        _loadProjectJson(dirUrl, function (data, url) {
            if (!data) {
                console.warn("HtmlWallpaperParser: no project.json in " + url);
                currentWallpaper = null;
                propertiesModel.clear();
                return;
            }
            currentWallpaper = _parseMetadata(url, data);
            _parseProperties(data.general && data.general.properties);
            wallpaperParsed(currentWallpaper);
        });
    }

    // —— project.json 异步读取（QML 的 XMLHttpRequest 支持 file://，Qt 6.5+ 全局 JSON.parse）——
    function _loadProjectJson(dirUrl, onDone) {
        const xhr = new XMLHttpRequest();
        xhr.open("GET", _pathJoin(dirUrl, "project.json"));
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE) {
                return;
            }
            // file:// 协议在 Qt 的 XHR 实现中返回 200（个别环境为 0）
            if (xhr.status !== 200 && xhr.status !== 0) {
                onDone(null, dirUrl);
                return;
            }
            let data = null;
            try {
                data = JSON.parse(xhr.responseText);
            } catch (e) {
                console.warn("HtmlWallpaperParser: invalid JSON in " + _pathJoin(dirUrl, "project.json") + " (" + e + ")");
            }
            onDone(data, dirUrl);
        };
        xhr.send();
    }

    // 把 project.json 顶层对象整理成统一的壁纸元数据；非 web 类型返回 null
    function _parseMetadata(dirUrl, data) {
        if (requireWebType && data.type && String(data.type).toLowerCase().indexOf("web") < 0) {
            return null;
        }
        const name = _basename(dirUrl);
        const entryFile = data.file || "index.html";
        const previewFile = data.preview || "";
        return {
            "name": name,
            "title": data.title || name,
            "description": data.description || "",
            "tags": data.tags || [],
            "type": data.type || "web",
            "visibility": data.visibility || "",
            "workshopid": String(data.workshopid || ""),
            "path": dirUrl,
            "entry": _pathJoin(dirUrl, entryFile),
            "preview": previewFile ? _pathJoin(dirUrl, previewFile) : ""
        };
    }

    // 解析 general.properties 为排序后的属性模型（未定义字段保持空/undefined，由 UI 按 type 兜底）
    function _parseProperties(properties) {
        propertiesModel.clear();
        if (!properties) {
            return;
        }
        const keys = Object.keys(properties);
        // 按 order 升序；无 order 的属性排到最后
        keys.sort(function (a, b) {
            return ((properties[a].order !== undefined ? properties[a].order : Number.MAX_SAFE_INTEGER)
                    - (properties[b].order !== undefined ? properties[b].order : Number.MAX_SAFE_INTEGER));
        });
        for (let i = 0; i < keys.length; i++) {
            const key = keys[i];
            const p = properties[key];
            propertiesModel.append({
                "key": key,
                "type": p.type || "text",
                "text": p.text || key,
                "value": p.value !== undefined ? p.value : _defaultValue(p),
                "min": p.min,
                "max": p.max,
                "step": p.step,
                "fraction": p.fraction,
                "precision": p.precision,
                "options": p.options || [],
                "condition": p.condition || "",
                "group": p.group || "",
                "order": p.order !== undefined ? p.order : Number.MAX_SAFE_INTEGER
            });
        }
    }

    // 属性 value 缺失时的兜底默认值
    function _defaultValue(p) {
        switch (p.type) {
        case "bool":
            return false;
        case "slider":
            return p.min !== undefined ? p.min : 0;
        case "combo":
            return (p.options && p.options.length) ? p.options[0].value : 0;
        case "color":
            return "0 0 0";
        default:
            return "";
        }
    }

    // —— 属性注入辅助 ——

    // 把 currentProperties 序列化成 query string（?k=v&...）
    // color 转成 #RRGGBB；bool 转 true/false；空值跳过
    function buildQueryString() {
        let parts = [];
        for (let i = 0; i < propertiesModel.count; i++) {
            const item = propertiesModel.get(i);
            let v = item.value;
            if (v === undefined || v === null || v === "") {
                continue;
            }
            if (typeof v === "boolean") {
                v = v ? "true" : "false";
            } else if (item.type === "color") {
                v = _colorToHex(v);
            }
            parts.push(encodeURIComponent(item.key) + "=" + encodeURIComponent(v));
        }
        return parts.join("&");
    }

    // 把当前属性拼到入口 HTML 的 URL 上（页面可用 location.search 读取参数）
    function applyPropertiesToUrl(baseUrl) {
        const query = buildQueryString();
        const s = String(baseUrl);
        if (!query) {
            return s;
        }
        return s + (s.indexOf("?") >= 0 ? "&" : "?") + query;
    }

    // Wallpaper Engine 颜色值 "R G B"（各 0~1）→ "#RRGGBB"
    function colorToHex(value) {
        return _colorToHex(value);
    }
    function _colorToHex(value) {
        if (typeof value !== "string") {
            return "#000000";
        }
        const parts = value.trim().split(/\s+/).map(parseFloat).slice(0, 3);
        if (parts.length !== 3 || parts.some(isNaN)) {
            return "#000000";
        }
        function toHex(v) {
            const h = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16);
            return h.length < 2 ? "0" + h : h;
        }
        return "#" + toHex(parts[0]) + toHex(parts[1]) + toHex(parts[2]);
    }

    // —— 路径工具 ——

    function _toUrl(p) {
        const s = String(p);
        return s.indexOf("://") >= 0 ? s : "file://" + s;
    }

    function _pathJoin(a, b) {
        const sa = String(a).replace(/\/+$/, "");
        const sb = String(b).replace(/^\/+/, "");
        return sa + "/" + sb;
    }

    function _basename(url) {
        const s = String(url).replace(/\/+$/, "");
        return s.substring(s.lastIndexOf("/") + 1);
    }
}
