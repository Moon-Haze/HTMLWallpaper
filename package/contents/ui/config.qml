import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: root
    twinFormLayouts: parentLayout

    property alias cfg_DisplayPage: displayPageField.text
    property alias cfg_ZoomFactor: zoomFactorSlider.value
    property alias cfg_InsecureHTTPS: insecureHTTPSCheckBox.checked

    TextField {
        id: displayPageField
        Kirigami.FormData.label: i18nd("plasma_wallpaper_com.github.Moon-Haze.htmlwallpaper", "URL:")
        Layout.fillWidth: true
        placeholderText: i18nd("plasma_wallpaper_com.github.Moon-Haze.htmlwallpaper", 
                                "https://yourwebsite.com 或 file:///absolute/path/to/your/website.html")
        ToolTip.visible: hovered
        ToolTip.text: displayPageField.text
    }

    RowLayout {
        Kirigami.FormData.label: i18nd("plasma_wallpaper_com.github.Moon-Haze.htmlwallpaper", "Zoom:")

        Slider {
            id: zoomFactorSlider
            Layout.fillWidth: true
            from: 0.5
            to: 3.0
            stepSize: 0.1
            snapMode: Slider.SnapAlways
        }

        Label {
            text: zoomFactorSlider.value.toFixed(1)
            Layout.minimumWidth: Kirigami.Units.gridUnit * 2
            horizontalAlignment: Text.AlignRight
        }
    }

    CheckBox {
        id: insecureHTTPSCheckBox
        Kirigami.FormData.label: i18nd("plasma_wallpaper_com.github.Moon-Haze.htmlwallpaper", "Insecure HTTPS")
        ToolTip.visible: hovered
        ToolTip.text: i18nd("plasma_wallpaper_com.github.Moon-Haze.htmlwallpaper", "Ignore HTTPS certificate errors")
    }

    Item {
        Layout.fillHeight: true
    }
}
