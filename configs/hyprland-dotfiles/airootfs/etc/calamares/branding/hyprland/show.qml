/* Calamares slideshow — Material You dark theme
   Matches end-4/dots-hyprland illogical-impulse aesthetic
*/
import QtQuick 2.15
import calamares.slideshow 1.0

Presentation {
    id: presentation

    function next() { presentation.goToNextSlide() }

    Timer {
        id: timer
        interval: 6000
        repeat: true
        running: false
        onTriggered: presentation.next()
    }
    onActivate: { timer.running = true }
    onLeave:    { timer.running = false }

    // ── Slide 1: Welcome ──────────────────────────────────────────────────
    Slide {
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            color: "#1c1b1f"
        }

        Image {
            anchors.fill: parent
            source: "welcome.png"
            fillMode: Image.PreserveAspectCrop
            opacity: 0.08
        }

        // Decorative accent circle
        Rectangle {
            width: 300
            height: 300
            radius: 150
            color: "#d0bcff"
            opacity: 0.05
            anchors.right: parent.right
            anchors.rightMargin: -60
            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            anchors.centerIn: parent
            spacing: 16

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Arch Linux Hyprland"
                font.pixelSize: 36
                font.weight: Font.Light
                font.family: "Google Sans Flex, Rubik, Noto Sans"
                color: "#e6e1e5"
                letterSpacing: -0.5
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 48
                height: 3
                radius: 2
                color: "#d0bcff"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "illogical-impulse dotfiles"
                font.pixelSize: 18
                font.family: "Google Sans Flex, Rubik, Noto Sans"
                color: "#d0bcff"
                font.weight: Font.Medium
            }

            Item { height: 8 }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Setting up your system — this may take a few minutes"
                font.pixelSize: 14
                font.family: "Google Sans Flex, Rubik, Noto Sans"
                color: "#79747e"
            }
        }

        // Slide indicator dots
        Row {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 20
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            Repeater {
                model: 4
                Rectangle {
                    width: index === 0 ? 24 : 8
                    height: 8
                    radius: 4
                    color: index === 0 ? "#d0bcff" : "#49454f"
                    Behavior on width { NumberAnimation { duration: 200 } }
                }
            }
        }
    }

    // ── Slide 2: What's included ──────────────────────────────────────────
    Slide {
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            color: "#1c1b1f"
        }

        Column {
            anchors.centerIn: parent
            spacing: 20
            width: 560

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "What's being installed"
                font.pixelSize: 26
                font.weight: Font.Light
                font.family: "Google Sans Flex, Rubik, Noto Sans"
                color: "#e6e1e5"
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 40
                height: 3
                radius: 2
                color: "#d0bcff"
            }

            Grid {
                anchors.horizontalCenter: parent.horizontalCenter
                columns: 2
                spacing: 12
                width: parent.width

                Repeater {
                    model: [
                        "Hyprland compositor",
                        "Quickshell status bar",
                        "PipeWire audio stack",
                        "Bluetooth & printing",
                        "NetworkManager",
                        "Material You theming",
                        "matugen color engine",
                        "illogical-impulse dotfiles"
                    ]
                    delegate: Rectangle {
                        width: 260
                        height: 40
                        radius: 20
                        color: "#2a2831"
                        border.color: "#312e3b"
                        border.width: 1

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 14
                            spacing: 10

                            Rectangle {
                                width: 8
                                height: 8
                                radius: 4
                                color: "#d0bcff"
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                text: modelData
                                color: "#cac4d0"
                                font.pixelSize: 13
                                font.family: "Google Sans Flex, Rubik, Noto Sans"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }
        }

        Row {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 20
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            Repeater {
                model: 4
                Rectangle {
                    width: index === 1 ? 24 : 8
                    height: 8
                    radius: 4
                    color: index === 1 ? "#d0bcff" : "#49454f"
                }
            }
        }
    }

    // ── Slide 3: matugen theming ──────────────────────────────────────────
    Slide {
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            color: "#1c1b1f"
        }

        Column {
            anchors.centerIn: parent
            spacing: 20
            width: 500

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Adaptive theming with matugen"
                font.pixelSize: 26
                font.weight: Font.Light
                font.family: "Google Sans Flex, Rubik, Noto Sans"
                color: "#e6e1e5"
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                width: parent.width
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 40
                height: 3
                radius: 2
                color: "#d0bcff"
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Your desktop colors are generated from your wallpaper using Google's Material You algorithm. Change your wallpaper and the entire system theme updates automatically."
                font.pixelSize: 14
                font.family: "Google Sans Flex, Rubik, Noto Sans"
                color: "#79747e"
                wrapMode: Text.WordWrap
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                lineHeight: 1.5
            }

            // Color palette preview
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                Repeater {
                    model: ["#d0bcff", "#ccc2dc", "#efb8c8", "#67523d", "#846CA7", "#9c8ab4"]
                    Rectangle {
                        width: 40
                        height: 40
                        radius: 20
                        color: modelData
                    }
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Default palette from default wallpaper"
                font.pixelSize: 11
                font.family: "Google Sans Flex, Rubik, Noto Sans"
                color: "#49454f"
            }
        }

        Row {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 20
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            Repeater {
                model: 4
                Rectangle {
                    width: index === 2 ? 24 : 8
                    height: 8
                    radius: 4
                    color: index === 2 ? "#d0bcff" : "#49454f"
                }
            }
        }
    }

    // ── Slide 4: After installation ───────────────────────────────────────
    Slide {
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            color: "#1c1b1f"
        }

        Column {
            anchors.centerIn: parent
            spacing: 20
            width: 500

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "After installation"
                font.pixelSize: 26
                font.weight: Font.Light
                font.family: "Google Sans Flex, Rubik, Noto Sans"
                color: "#e6e1e5"
            }

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 40
                height: 3
                radius: 2
                color: "#d0bcff"
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12
                width: parent.width

                Repeater {
                    model: [
                        ["Super + Return", "Open terminal"],
                        ["Super + R", "App launcher"],
                        ["Super + E", "File manager"],
                        ["Super + Q", "Close window"],
                        ["Right sidebar", "Wallpaper & theme switcher"]
                    ]
                    delegate: Rectangle {
                        width: parent.width
                        height: 42
                        radius: 12
                        color: "#2a2831"

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 16
                            anchors.right: parent.right
                            anchors.rightMargin: 16
                            spacing: 0

                            Rectangle {
                                width: keybind.width + 20
                                height: 26
                                radius: 6
                                color: "#312e3b"
                                border.color: "#49454f"
                                border.width: 1
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    id: keybind
                                    anchors.centerIn: parent
                                    text: modelData[0]
                                    color: "#d0bcff"
                                    font.pixelSize: 12
                                    font.family: "JetBrains Mono NF, monospace"
                                    font.weight: Font.Medium
                                }
                            }

                            Item { width: 12 }

                            Text {
                                text: modelData[1]
                                color: "#cac4d0"
                                font.pixelSize: 13
                                font.family: "Google Sans Flex, Rubik, Noto Sans"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }
            }
        }

        Row {
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 20
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            Repeater {
                model: 4
                Rectangle {
                    width: index === 3 ? 24 : 8
                    height: 8
                    radius: 4
                    color: index === 3 ? "#d0bcff" : "#49454f"
                }
            }
        }
    }
}
