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

    // Step pretty-name → Material Symbol ligature.
    //
    // Keyed by the module's prettyName() (which is what the ViewManager
    // model exposes as `display`) instead of position, so inserting or
    // removing a step in settings.conf doesn't silently shift every
    // icon down by one. Entries for both the raw netinstall pretty
    // name ("Package selection") and our post-override label ("Apps")
    // are kept so the lookup is robust either way.
    readonly property var stepIcons: ({
        "Welcome":           "waving_hand",
        "Location":          "globe",                  // locale module's prettyName
        "Keyboard":          "keyboard",
        "Partitions":        "storage",
        "Users":             "contacts_product",
        "Get Started":       "rocket_launch",          // installmethod picker
        "Apps":              "deployed_code_update",   // post-override label
        "Package selection": "deployed_code_update",   // raw netinstall prettyName
        "Summary":           "inactive_order",
        "Install":           "install_desktop",        // ExecutionViewStep
        "Set Up":            "install_desktop",        // setupMode variant
        "Finish":            "inventory"
    })

    // QML-side label override, keyed by Calamares' built-in display
    // string. Keeps the netinstall section labeled "Apps" without
    // touching .qm files. New entries can be added here for any
    // module whose prettyName we want to rename in the sidebar.
    readonly property var stepLabelOverrides: ({
        "Package selection": "Apps"
    })

    // Insert a separator AFTER these steps (keyed by their post-override
    // display label). Two visual groups:
    //   "Welcome" alone at top,
    //   then setup pages up through "Apps" / Install Method / etc.,
    //   then Summary · Install · Finished.
    readonly property var separatorAfter: ({
        "Welcome": true,
        "Apps":    true
    })

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
                        stepText: root.stepLabelOverrides[display] !== undefined
                                  ? root.stepLabelOverrides[display]
                                  : display
                    }

                    // Separator container — collapses to 0 when this step
                    // is not the tail of a group. Keyed off post-override
                    // label so reordering settings.conf can't desync it.
                    Item {
                        Layout.fillWidth: true
                        visible: root.separatorAfter[
                            root.stepLabelOverrides[display] !== undefined
                                ? root.stepLabelOverrides[display]
                                : display
                        ] === true
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
                // Name-keyed lookup so a sequence reorder doesn't desync
                // icons. Falls back to a neutral circle for any module
                // whose pretty name we haven't mapped yet.
                text:       root.stepIcons[navBtn.stepText] || "radio_button_unchecked"
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
