/* =============================================================================
 * calamares-sidebar.qml
 * Mainstream Dotfiles Installer — Vertical Navigation Rail
 *
 * Mirrors dots-hyprland Quickshell settings.qml SettingsNavButton:
 *   ColumnLayout of 56px-tall full-rounded pills, icon + label horizontal,
 *   secondaryContainer fill when toggled, surfaceContainerHigh on hover,
 *   group separators (1px outlineVariant @ 0.3 opacity, 12px margins).
 *
 * Color system: M3 dark scheme, mirrored from Appearance.qml live snapshot.
 * Icons:        Material Symbols Rounded — installed via mainstream-fonts-themes.
 * =========================================================================== */

import QtQuick 2.15
import QtQuick.Controls
import QtQuick.Layouts 1.15
import io.calamares.core 1.0
import io.calamares.ui 1.0

Rectangle {
    id: root
    // QQuickWidget clears to opaque white before QML paints, so a transparent
    // root would leak that through. Paint m3background here to seamlessly
    // continue the parent window's surface.
    color: "#141313"                // m3background

    // ── M3 dark palette (from Appearance.qml live snapshot) ─────────────────
    readonly property color colOnSurface:    "#e6e1e1"   // m3onBackground
    readonly property color colOnSurfaceVar: "#cbc5ca"   // m3onSurfaceVariant
    readonly property color colSurfContHi:   "#2b2a2a"   // m3surfaceContainerHigh — hover
    readonly property color colSecCont:      "#4d4b4d"   // m3secondaryContainer  — active pill
    readonly property color colOnSecCont:    "#ece6e9"   // m3onSecondaryContainer
    readonly property color colOutlineVar:   "#49464a"   // m3outlineVariant      — divider

    // Step → Material Symbol ligature. Order follows settings.conf `show:` plus
    // the auto-inserted ExecutionViewStep that runs between Summary and Finished.
    readonly property var stepIcons: [
        "waving_hand",            // Welcome
        "globe",                  // Locale
        "keyboard",               // Keyboard
        "storage",                // Partitions
        "contacts_product",       // Users
        "deployed_code_update",   // Apps (netinstall)
        "inactive_order",         // Summary
        "install_desktop",        // Install (ExecutionViewStep)
        "inventory"               // Finished
    ]

    // Optional QML-side label override — keyed by step index so Calamares'
    // built-in module display string can be replaced without editing .qm files.
    readonly property var stepLabelOverrides: ({
        5: "Apps"                 // netinstall → "Package Selection" → "Apps"
    })

    // Insert a separator AFTER these indices. Groupings:
    //   [0]      Welcome
    //   [1..5]   Locale · Keyboard · Partitions · Users · Apps
    //   [6..8]   Summary · Install · Finished
    readonly property var separatorAfter: [0, 5]

    readonly property int currentStep: ViewManager.currentStepIndex

    Flickable {
        id: navFlickable
        anchors { fill: parent; margins: 5 }
        clip: true
        contentWidth: width
        contentHeight: navColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AlwaysOff }

        ColumnLayout {
            id: navColumn
            width: parent.width
            spacing: 0

            Repeater {
                model: ViewManager

                // Per-step delegate: pill button + optional separator block.
                delegate: ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    SettingsNavButton {
                        Layout.fillWidth: true
                        stepIdx: index
                        stepText: root.stepLabelOverrides[index] !== undefined
                                  ? root.stepLabelOverrides[index]
                                  : display
                    }

                    // Separator container — collapses to 0 when not in this group's tail.
                    Item {
                        Layout.fillWidth: true
                        visible: root.separatorAfter.indexOf(index) !== -1
                        implicitHeight: visible ? 25 : 0   // 12 above + 1 line + 12 below

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width - 24
                            height: 1
                            color: root.colOutlineVar
                            opacity: 0.3
                        }
                    }
                }
            }
        }
    }

    // ── Pill button (visual-only — Calamares progresses via Back/Next) ──────
    component SettingsNavButton: Item {
        id: navBtn
        property int stepIdx: 0
        property string stepText: ""

        readonly property bool isCurrent:   stepIdx === root.currentStep
        readonly property bool isCompleted: stepIdx <  root.currentStep
        readonly property bool isFuture:    stepIdx >  root.currentStep

        implicitHeight: 56

        // Pill background — fills width, full height-radius for stadium shape.
        Rectangle {
            id: pillBg
            anchors.fill: parent
            radius: height / 2
            color: navBtn.isCurrent
                       ? root.colSecCont
                       : (hover.hovered ? root.colSurfContHi : "transparent")
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        HoverHandler { id: hover }

        // Icon area — fixed 56px square on the left (matches SettingsNavButton.baseSize).
        Item {
            id: iconBox
            width: 56
            height: 32
            anchors { left: parent.left; verticalCenter: parent.verticalCenter }

            Text {
                anchors.centerIn: parent
                font.family:    "Material Symbols Rounded"
                font.pixelSize: 22
                font.weight:    (navBtn.isCurrent || hover.hovered) ? Font.DemiBold : Font.Normal
                // FILL animates outline ↔ filled; opsz tracks pixel size.
                font.variableAxes: ({
                    "FILL": (navBtn.isCurrent || navBtn.isCompleted) ? 1 : 0,
                    "opsz": 22
                })
                renderType: Text.NativeRendering
                text:       root.stepIcons[navBtn.stepIdx] || "radio_button_unchecked"
                // Sidebar entries always render at full strength — current pill
                // uses onSecondaryContainer, every other step uses onBackground.
                color:      navBtn.isCurrent ? root.colOnSecCont : root.colOnSurface
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }

        // Step label — right of the icon.
        Text {
            anchors { left: iconBox.right; verticalCenter: iconBox.verticalCenter }
            text:           navBtn.stepText
            font.pixelSize: 14
            font.weight:    navBtn.isCurrent ? Font.Medium : Font.Normal
            renderType:     Text.NativeRendering
            color:          navBtn.isCurrent ? root.colOnSecCont : root.colOnSurface
            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }
}
