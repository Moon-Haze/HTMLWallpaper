
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import org.kde.kirigami as Kirigami


Kirigami.FormLayout {
    id: root
    twinFormLayouts: parentLayout
    property alias cfg_DisplayPage: displayPageField.text
    property alias cfg_ZoomFactor: zoomFactorSlider.value
    property alias cfg_InsecureHTTPS: insecureHTTPSCheckBox.checked

    RowLayout {
        Layout.topMargin: 10
        spacing: 10

        Label {
            Layout.minimumWidth: width
            Layout.maximumWidth: width
            width: formAlignment - 20
            horizontalAlignment: Text.AlignRight

            text: i18nd("plasma_wallpaper_com.github.Moon-Haze.HTMLWallpaper", "URL:")
        }
        TextField {
            id: displayPageField
            Layout.minimumWidth: width
            Layout.maximumWidth: width
            width: 320
        }
    }

    RowLayout {
        spacing: 10

        Label {
            Layout.minimumWidth: width
            Layout.maximumWidth: width
            width: formAlignment - 20
            horizontalAlignment: Text.AlignRight

            text: i18nd("plasma_wallpaper_com.github.Moon-Haze.HTMLWallpaper", "Web:")
        }
        Label {
            Layout.minimumWidth: width
            Layout.maximumWidth: width
            width: formAlignment - 20
            horizontalAlignment: Text.AlignLeft

            text: i18nd("plasma_wallpaper_com.github.Moon-Haze.HTMLWallpaper", " https://yourwebsite.com")
        }
    }

    RowLayout {
        spacing: 10

        Label {
            Layout.minimumWidth: width
            Layout.maximumWidth: width
            width: formAlignment - 20
            horizontalAlignment: Text.AlignRight

            text: i18nd("plasma_wallpaper_com.github.Moon-Haze.HTMLWallpaper", "Local:")
        }
        Label {
            Layout.minimumWidth: width
            Layout.maximumWidth: width
            width: formAlignment - 20
            horizontalAlignment: Text.AlignLeft

            text: i18nd("plasma_wallpaper_com.github.Moon-Haze.HTMLWallpaper", " file:///absolute/path/to/your/website.html")
        }
    }
        
    RowLayout {
        spacing: 10

        Label {
            Layout.minimumWidth: width
            Layout.maximumWidth: width
            width: formAlignment - 20
            horizontalAlignment: Text.AlignRight

            text: i18nd("plasma_wallpaper_com.github.Moon-Haze.HTMLWallpaper", "Zoom:")
        }
        Slider{
            id: zoomFactorSlider
            from: 0.5
            to: 3.0
            stepSize: 0.5
            snapMode: Slider.SnapAlways
        }
    }

    RowLayout {
        spacing: 10

        Label {
            Layout.minimumWidth: width
            Layout.maximumWidth: width
            width: formAlignment - 20
            horizontalAlignment: Text.AlignRight
        }
        Label {
            Layout.minimumWidth: width
            Layout.maximumWidth: width
            width: formAlignment - 20
            horizontalAlignment: Text.AlignLeft

            text: i18nd("plasma_wallpaper_com.github.Moon-Haze.HTMLWallpaper", "0.5       1       1.5        2       2.5       3")
        }
    }

    RowLayout {
        spacing: 10

        Label {
            Layout.minimumWidth: width
            Layout.maximumWidth: width
            width: formAlignment - 20
            horizontalAlignment: Text.AlignRight

            text: i18nd("plasma_wallpaper_com.github.Moon-Haze.HTMLWallpaper", "Insecure HTTPS")
        }
        CheckBox {
            id: insecureHTTPSCheckBox

            ToolTip {
                text: i18nd("plasma_wallpaper_com.github.Moon-Haze.HTMLWallpaper", "Ignore HTTPS errors")
                visible: parent.hovered
            }
        }
    }

    Item {
        Layout.fillHeight: true
    }
}
