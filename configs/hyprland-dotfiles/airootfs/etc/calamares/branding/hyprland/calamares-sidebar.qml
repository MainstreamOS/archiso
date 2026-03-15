/* Calamares sidebar — Material You dark theme
   Matches end-4/dots-hyprland illogical-impulse aesthetic
*/

import io.calamares.ui 1.0
import io.calamares.core 1.0

import QtQuick 2.15
import QtQuick.Layouts 1.3
import QtQuick.Controls 2.15

Rectangle {
    id: sideBar
    color: "#1c1b1f"
    height: 52
    width: parent ? parent.width : 1100

    // Subtle bottom border
    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        color: "#49454f"
        opacity: 0.5
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 4

        // Logo
        Image {
            Layout.alignment: Qt.AlignVCenter
            Layout.rightMargin: 8
            id: logo
            width: 28
            height: 28
            source: "file:/" + Branding.imagePath(Branding.ProductLogo)
            sourceSize.width: width
            sourceSize.height: height
            smooth: true
        }

        // Product name
        Text {
            Layout.alignment: Qt.AlignVCenter
            Layout.rightMargin: 16
            text: Branding.shortProductName
            color: "#e6e1e5"
            font.pixelSize: 13
            font.weight: Font.Medium
            font.family: "Google Sans Flex, Rubik, Noto Sans"
        }

        // Thin divider
        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            width: 1
            height: 24
            color: "#49454f"
            Layout.rightMargin: 8
        }

        // Step pills
        Repeater {
            model: ViewManager
            delegate: Item {
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: true
                height: 36

                Rectangle {
                    id: pill
                    anchors.fill: parent
                    radius: 18
                    color: index === ViewManager.currentStepIndex
                        ? "#2d2a3e"
                        : "transparent"

                    // Active indicator line at bottom
                    Rectangle {
                        visible: index === ViewManager.currentStepIndex
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.width * 0.6
                        height: 2
                        radius: 1
                        color: "#d0bcff"
                    }

                    // Step number bubble
                    Rectangle {
                        id: stepNum
                        visible: index !== ViewManager.currentStepIndex
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20
                        height: 20
                        radius: 10
                        color: index < ViewManager.currentStepIndex
                            ? "#d0bcff"
                            : "#312e3b"

                        Text {
                            anchors.centerIn: parent
                            text: (index + 1).toString()
                            color: index < ViewManager.currentStepIndex
                                ? "#381e72"
                                : "#79747e"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            font.family: "Google Sans Flex, Rubik, Noto Sans"
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: index !== ViewManager.currentStepIndex
                            ? stepNum.right
                            : parent.left
                        anchors.leftMargin: index !== ViewManager.currentStepIndex ? 6 : 12
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        text: display
                        elide: Text.ElideRight
                        color: index === ViewManager.currentStepIndex
                            ? "#d0bcff"
                            : index < ViewManager.currentStepIndex
                                ? "#cac4d0"
                                : "#79747e"
                        font.pixelSize: index === ViewManager.currentStepIndex ? 13 : 12
                        font.weight: index === ViewManager.currentStepIndex
                            ? Font.Medium
                            : Font.Normal
                        font.family: "Google Sans Flex, Rubik, Noto Sans"
                    }

                    Behavior on color {
                        ColorAnimation { duration: 200 }
                    }
                }
            }
        }
    }
}
