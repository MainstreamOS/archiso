/* Calamares Slideshow for Arch Linux Hyprland */
import QtQuick 2.0
import calamares.slideshow 1.0

Presentation {
    id: presentation

    function next() { presentation.goToNextSlide(); }
    Timer {
        id: timer
        interval: 5000
        repeat: true
        running: false
        onTriggered: presentation.next()
    }
    onActivate: { timer.running = true; }
    onLeave:    { timer.running = false; }

    Slide {
        anchors.fill: parent
        Image {
            id: background
            source: "welcome.png"
            fillMode: Image.PreserveAspectCrop
            anchors.fill: parent
            opacity: 0.3
        }
        Column {
            anchors.centerIn: parent
            spacing: 20
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Installing Arch Linux Hyprland"
                font.pixelSize: 28
                font.bold: true
                color: "#ffffff"
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Setting up your system with Hyprland + illogical-impulse dotfiles"
                font.pixelSize: 16
                color: "#cccccc"
                wrapMode: Text.WordWrap
                width: 600
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    Slide {
        anchors.fill: parent
        Column {
            anchors.centerIn: parent
            spacing: 20
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "What's being installed?"
                font.pixelSize: 24
                font.bold: true
                color: "#ffffff"
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "• Hyprland window manager\n• Quickshell-based status bar\n• Full audio stack (PipeWire)\n• Bluetooth & printing support\n• NetworkManager for WiFi\n• illogical-impulse dotfiles & themes"
                font.pixelSize: 14
                color: "#cccccc"
                width: 500
                horizontalAlignment: Text.AlignLeft
            }
        }
    }

    Slide {
        anchors.fill: parent
        Column {
            anchors.centerIn: parent
            spacing: 20
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "After Installation"
                font.pixelSize: 24
                font.bold: true
                color: "#ffffff"
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "On first boot, the dotfiles setup will complete automatically.\n\nThis installs AUR packages, configures services,\nand sets up your desktop environment.\n\nInternet connection required on first boot."
                font.pixelSize: 14
                color: "#cccccc"
                width: 500
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }
    }
}
