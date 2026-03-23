/* =============================================================================
 * installchoice.qml
 * Mainstream Dotfiles Installer — Install Choice + Package Selection
 *
 * Page 1: Three radio-card options (Default / Customize / OS Only).
 * Page 2: Package category tree with checkboxes (Customize only).
 *
 * Replaces the built-in netinstall module so that Default and OS Only can
 * skip the package-selection step entirely via isAtEnd().
 *
 * Writes GlobalStorage "packageOperations" in onLeave() for the packages
 * exec module.
 *
 * Color system: Material Design 3 dark scheme (seed #6750A4).
 * Icons: Material Symbols Rounded (variable font, ligature rendering).
 * =========================================================================== */

import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import io.calamares.core 1.0
import io.calamares.ui 1.0


Item {
    id: root

    /* ── M3 dark color tokens ─────────────────────────────────────────────── */
    readonly property color colBg:             "#141218"
    readonly property color colSurface:        "#1d1b20"
    readonly property color colSurfaceCont:    "#211f26"
    readonly property color colSurfaceHigh:    "#2b2930"
    readonly property color colSurfaceHighest: "#36343b"
    readonly property color colOnSurface:      "#e6e1e6"
    readonly property color colOnSurfaceVar:   "#cac4d0"
    readonly property color colPrimary:        "#cfbcff"
    readonly property color colSecCont:        "#4a4458"
    readonly property color colOnSecCont:      "#e8def8"
    readonly property color colOutline:        "#938f99"
    readonly property color colOutlineVar:     "#49454f"

    /* ── State ────────────────────────────────────────────────────────────── */
    property int    currentPage:    0           // 0 = choice, 1 = packages
    property string installChoice:  "default"   // "default" | "customize" | "minimal"
    property var    groupExpanded:  ({})         // group index → bool
    property var    pkgChecked:     ({})         // "groupIdx:pkgIdx" → bool

    /* ── Package data (mirrors netinstall.conf) ───────────────────────────── */
    readonly property var packageGroups: [
        {
            name: "Included Extras",
            icon: "deployed_code",
            defaultSelected: true,
            packages: [
                { name: "google-chrome",     desc: "Google Chrome — full Chrome with DRM and Widevine support. (AUR)" },
                { name: "resources",         desc: "Resources — modern GTK4 system monitor for CPU, memory, GPU, and disks." },
                { name: "gnome-disk-utility",desc: "GNOME Disks — manage drives, partitions, and disk images." },
                { name: "gnome-software",    desc: "GNOME Software — graphical app store for Flatpak and system packages." },
                { name: "appstream",         desc: "AppStream — metadata for software catalogs (needed by GNOME Software)." },
                { name: "appstream-glib",    desc: "AppStream GLib — library for reading AppStream metadata." },
                { name: "flatpak",           desc: "Flatpak — sandboxed app distribution framework." },
                { name: "gnome-calculator",  desc: "GNOME Calculator — simple and scientific calculator." },
                { name: "gnome-calendar",    desc: "GNOME Calendar — clean, easy-to-use calendar app." },
                { name: "simple-scan",       desc: "Simple Scan — straightforward scanning utility." },
                { name: "gnome-font-viewer", desc: "GNOME Font Viewer — preview and install fonts." },
                { name: "impression",        desc: "Impression — write disk images to USB drives. (AUR)" },
                { name: "libreoffice-fresh", desc: "LibreOffice — full office suite (Writer, Calc, Impress, etc.)." },
                { name: "gnome-text-editor", desc: "GNOME Text Editor — simple, modern text editor." },
                { name: "mpv",               desc: "mpv — lightweight, scriptable video player." },
                { name: "mpv-modernz",       desc: "mpv ModernZ — modern OSC skin for mpv. (AUR)" },
                { name: "mpv-thumbfast",     desc: "mpv thumbfast — thumbnail previews on the mpv seekbar. (AUR)" },
                { name: "spotify",           desc: "Spotify — official music streaming client. (AUR)" },
                { name: "satty",             desc: "Satty — modern screenshot annotation tool. (AUR)" },
                { name: "loupe",             desc: "Loupe — modern GNOME image viewer with smooth zoom and gesture support." },
                { name: "gimp",              desc: "GIMP — full-featured image editor." },
                { name: "fastfetch",         desc: "Fastfetch — fast system info tool (neofetch replacement)." },
                { name: "topgrade",          desc: "Topgrade — update everything (pacman, AUR, flatpak, etc.) in one command. (AUR)" },
                { name: "localsend",         desc: "LocalSend — share files to nearby devices over Wi-Fi without internet. (AUR)" },
                { name: "ksshaskpass",       desc: "KSSHAskPass — KDE/Qt frontend for SSH passphrase prompts." }
            ]
        },
        {
            name: "Web Browsers",
            icon: "language",
            defaultSelected: false,
            packages: [
                { name: "firefox",        desc: "Mozilla Firefox — fast, private, and open-source web browser." },
                { name: "chromium",       desc: "Chromium — open-source base of Google Chrome." },
                { name: "google-chrome",  desc: "Google Chrome — full Chrome with DRM and Widevine support. (AUR)" },
                { name: "brave-bin",      desc: "Brave — privacy-focused browser with built-in ad blocking. (AUR)" },
                { name: "librewolf-bin",  desc: "LibreWolf — hardened Firefox fork with strict privacy defaults. (AUR)" }
            ]
        },
        {
            name: "Development Tools",
            icon: "code",
            defaultSelected: false,
            packages: [
                { name: "code",                   desc: "VS Code (OSS) — open-source code editor by Microsoft." },
                { name: "visual-studio-code-bin",  desc: "Visual Studio Code — proprietary Microsoft build with full marketplace. (AUR)" },
                { name: "alacritty",              desc: "Alacritty — blazing-fast GPU-accelerated terminal emulator." },
                { name: "neovim",                 desc: "Neovim — hyperextensible Vim-based terminal editor." },
                { name: "vim",                    desc: "Vim — classic, highly configurable terminal text editor." },
                { name: "jetbrains-toolbox",      desc: "JetBrains Toolbox — manage PyCharm, IDEA, and other JetBrains IDEs. (AUR)" },
                { name: "github-desktop-bin",     desc: "GitHub Desktop — official Git GUI client. (AUR)" },
                { name: "docker",                 desc: "Docker — build, ship, and run containerized applications." }
            ]
        },
        {
            name: "Media & Entertainment",
            icon: "music_note",
            defaultSelected: false,
            packages: [
                { name: "vlc",              desc: "VLC — versatile media player that plays virtually any format." },
                { name: "spotify",          desc: "Spotify — official streaming music client. (AUR)" },
                { name: "mpv",              desc: "mpv — lightweight, scriptable command-line video player." },
                { name: "plex-media-server",desc: "Plex — personal media server with a polished streaming interface. (AUR)" },
                { name: "jellyfin-server",  desc: "Jellyfin — free, open-source media server." },
                { name: "rhythmbox",        desc: "Rhythmbox — music player and library manager for GNOME." },
                { name: "lollypop",         desc: "Lollypop — modern music player with cover art and online radio." }
            ]
        },
        {
            name: "Productivity & Office",
            icon: "description",
            defaultSelected: false,
            packages: [
                { name: "libreoffice-fresh", desc: "LibreOffice — full-featured office suite." },
                { name: "obsidian",          desc: "Obsidian — powerful Markdown note-taking and knowledge base." },
                { name: "thunderbird",       desc: "Thunderbird — Mozilla email client with calendar and feed support." },
                { name: "okular",            desc: "Okular — feature-rich document viewer supporting PDF, ePub, and more." },
                { name: "evince",            desc: "Evince — lightweight PDF and document viewer for GNOME." },
                { name: "keepassxc",         desc: "KeePassXC — cross-platform, offline password manager." }
            ]
        },
        {
            name: "System & Utilities",
            icon: "shield",
            defaultSelected: false,
            packages: [
                { name: "htop",      desc: "htop — interactive process viewer and system monitor." },
                { name: "btop",      desc: "btop — beautiful, resource-efficient system monitor." },
                { name: "timeshift", desc: "Timeshift — system snapshot and restore tool (rsync or btrfs)." },
                { name: "flatseal",  desc: "Flatseal — graphical tool to manage Flatpak permissions." },
                { name: "stacer",    desc: "Stacer — system optimizer, cleaner, and service manager. (AUR)" },
                { name: "ventoy",    desc: "Ventoy — create bootable USB drives supporting multiple ISOs." }
            ]
        },
        {
            name: "Gaming",
            icon: "sports_esports",
            defaultSelected: false,
            packages: [
                { name: "steam",                      desc: "Steam — Valve's game distribution platform with Proton compatibility." },
                { name: "lutris",                     desc: "Lutris — open game manager with Wine and emulator frontend support." },
                { name: "heroic-games-launcher-bin",  desc: "Heroic — open-source launcher for Epic and GOG. (AUR)" },
                { name: "mangohud",                   desc: "MangoHud — in-game performance overlay (FPS, CPU, GPU, temps)." },
                { name: "protonplus",                 desc: "ProtonPlus — simple Proton version manager for Steam. (AUR)" },
                { name: "goverlay",                   desc: "GOverlay — graphical MangoHud, vkBasalt, and ReplaySorcery configurator. (AUR)" },
                { name: "bottles",                    desc: "Bottles — run Windows applications and games via Wine." }
            ]
        },
        {
            name: "Graphics & Creative",
            icon: "palette",
            defaultSelected: false,
            packages: [
                { name: "gimp",            desc: "GIMP — full-featured image editor, open-source Photoshop alternative." },
                { name: "inkscape",        desc: "Inkscape — professional vector graphics editor (SVG-based)." },
                { name: "kdenlive",        desc: "Kdenlive — powerful open-source non-linear video editor." },
                { name: "davinci-resolve", desc: "DaVinci Resolve — professional video editing and color grading. (AUR)" },
                { name: "blender",         desc: "Blender — open-source 3D modeling, animation, and rendering suite." }
            ]
        },
        {
            name: "Streaming",
            icon: "cast",
            defaultSelected: false,
            packages: [
                { name: "obs-studio",                  desc: "OBS Studio — free software for live streaming and screen recording." },
                { name: "obs-vkcapture",               desc: "obs-vkcapture — Vulkan/OpenGL game capture for OBS. (AUR)" },
                { name: "obs-pipewire-audio-capture",  desc: "obs-pipewire-audio-capture — capture app audio via PipeWire. (AUR)" },
                { name: "obs-studio-browser",          desc: "obs-studio-browser — browser source plugin for OBS. (AUR)" },
                { name: "obs-move-transition",         desc: "obs-move-transition — smooth move transitions for OBS sources. (AUR)" },
                { name: "v4l2loopback-dkms",           desc: "v4l2loopback — virtual camera kernel module for OBS virtual webcam." },
                { name: "ffmpeg",                      desc: "FFmpeg — complete multimedia framework for encoding and streaming." },
                { name: "obs-vaapi",                   desc: "obs-vaapi — VA-API hardware encoding for OBS (AMD/Intel). (AUR)" }
            ]
        },
        {
            name: "Communication",
            icon: "chat",
            defaultSelected: false,
            packages: [
                { name: "discord",           desc: "Discord — voice, video, and text chat for gaming and communities." },
                { name: "signal-desktop",    desc: "Signal — end-to-end encrypted messaging." },
                { name: "slack-desktop",     desc: "Slack — team messaging and collaboration platform. (AUR)" },
                { name: "zoom",              desc: "Zoom — video conferencing and webinar platform. (AUR)" },
                { name: "teams-for-linux",   desc: "Teams for Linux — unofficial Microsoft Teams client. (AUR)" },
                { name: "element-desktop",   desc: "Element — open-source Matrix client for decentralized chat." }
            ]
        }
    ]

    /* ── Default-mode package list (Included Extras) ──────────────────────── */
    readonly property var defaultPackages: (function() {
        var pkgs = []
        var group = packageGroups[0]  // Included Extras
        for (var i = 0; i < group.packages.length; i++)
            pkgs.push(group.packages[i].name)
        return pkgs
    })()

    /* ── Calamares interface ───────────────────────────────────────────────── */
    function prettyName() { return "Apps" }

    function onActivate() {
        initCheckedState()
    }

    function onLeave() {
        var ops = []
        if (installChoice === "default") {
            ops = [{ "try_install": defaultPackages }]
        } else if (installChoice === "customize") {
            var selected = getSelectedPackages()
            if (selected.length > 0)
                ops = [{ "try_install": selected }]
        }
        // "minimal" → empty ops, nothing installed
        Global.insert("packageOperations", ops)
    }

    function isAtEnd() {
        if (currentPage === 0)
            return installChoice !== "customize"
        return true
    }

    function isAtBeginning() {
        return currentPage === 0
    }

    function next() {
        if (currentPage === 0 && installChoice === "customize") {
            currentPage = 1
        }
    }

    function back() {
        if (currentPage === 1)
            currentPage = 0
    }

    /* ── Helpers ───────────────────────────────────────────────────────────── */
    function initCheckedState() {
        var c = {}
        for (var g = 0; g < packageGroups.length; g++) {
            var group = packageGroups[g]
            for (var p = 0; p < group.packages.length; p++) {
                c[g + ":" + p] = group.defaultSelected
            }
        }
        pkgChecked = c
        // Expand the first group by default
        groupExpanded = { "0": true }
    }

    function togglePkg(gIdx, pIdx) {
        var c = Object.assign({}, pkgChecked)
        var key = gIdx + ":" + pIdx
        c[key] = !c[key]
        pkgChecked = c
    }

    function toggleGroup(gIdx) {
        var group = packageGroups[gIdx]
        // If all checked → uncheck all, otherwise check all
        var allChecked = true
        for (var p = 0; p < group.packages.length; p++) {
            if (!pkgChecked[gIdx + ":" + p]) { allChecked = false; break }
        }
        var c = Object.assign({}, pkgChecked)
        for (var p2 = 0; p2 < group.packages.length; p2++) {
            c[gIdx + ":" + p2] = !allChecked
        }
        pkgChecked = c
    }

    function toggleExpand(gIdx) {
        var e = Object.assign({}, groupExpanded)
        e[gIdx] = !e[gIdx]
        groupExpanded = e
    }

    function groupCheckedCount(gIdx) {
        var group = packageGroups[gIdx]
        var count = 0
        for (var p = 0; p < group.packages.length; p++) {
            if (pkgChecked[gIdx + ":" + p]) count++
        }
        return count
    }

    function getSelectedPackages() {
        var selected = []
        for (var g = 0; g < packageGroups.length; g++) {
            var group = packageGroups[g]
            for (var p = 0; p < group.packages.length; p++) {
                if (pkgChecked[g + ":" + p])
                    selected.push(group.packages[p].name)
            }
        }
        return selected
    }


    /* ═════════════════════════════════════════════════════════════════════════
       PAGE 1 — CHOOSE YOUR EXPERIENCE
       ═════════════════════════════════════════════════════════════════════════ */
    Item {
        id: choicePage
        anchors.fill: parent
        visible: root.currentPage === 0

        ColumnLayout {
            anchors.fill: parent
            anchors.topMargin: 18
            anchors.bottomMargin: 12
            spacing: 0

            /* Title */
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Choose Your Experience"
                font.pixelSize: 28
                font.weight: Font.Medium
                color: root.colOnSurface
                renderType: Text.NativeRendering
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 6
                Layout.bottomMargin: 28
                text: "How would you like to set up your system?"
                font.pixelSize: 15
                color: root.colOnSurfaceVar
                renderType: Text.NativeRendering
            }

            /* Spacer */
            Item { Layout.fillHeight: true; Layout.maximumHeight: 20 }

            /* ── Option cards ─────────────────────────────────────────── */
            Repeater {
                model: [
                    {
                        key: "default",
                        icon: "widgets",
                        title: "Default Apps",
                        desc: "Everything you need for a complete desktop experience. " +
                              "Ideal for new Linux users, family computers, or anyone " +
                              "who wants a fully-equipped system right out of the box."
                    },
                    {
                        key: "customize",
                        icon: "tune",
                        title: "Customize Your Apps",
                        desc: "Hand-pick from a curated selection of popular Linux " +
                              "applications. Perfect if you know what you want or " +
                              "prefer to choose exactly what gets installed."
                    },
                    {
                        key: "minimal",
                        icon: "terminal",
                        title: "OS Only",
                        desc: "A clean slate with just the base system and desktop. " +
                              "For experienced users who prefer to build their own " +
                              "setup from scratch."
                    }
                ]

                delegate: Rectangle {
                    id: card
                    Layout.fillWidth: true
                    Layout.preferredHeight: 110
                    Layout.maximumWidth: 760
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: 16

                    readonly property bool isSelected: root.installChoice === modelData.key

                    radius: 16
                    color: isSelected ? root.colSecCont : root.colSurfaceCont
                    border.width: isSelected ? 0 : 1
                    border.color: root.colOutlineVar

                    Behavior on color { ColorAnimation { duration: 180 } }
                    Behavior on border.color { ColorAnimation { duration: 180 } }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.installChoice = modelData.key
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 24
                        anchors.rightMargin: 28
                        spacing: 0

                        /* Radio indicator */
                        Rectangle {
                            Layout.preferredWidth: 22
                            Layout.preferredHeight: 22
                            Layout.alignment: Qt.AlignVCenter
                            radius: 11
                            color: "transparent"
                            border.width: 2
                            border.color: card.isSelected ? root.colPrimary : root.colOutline

                            Behavior on border.color { ColorAnimation { duration: 180 } }

                            Rectangle {
                                anchors.centerIn: parent
                                width: 12; height: 12; radius: 6
                                color: root.colPrimary
                                visible: card.isSelected
                            }
                        }

                        Item { width: 20 }

                        /* Large icon */
                        Rectangle {
                            Layout.preferredWidth: 80
                            Layout.preferredHeight: 80
                            Layout.alignment: Qt.AlignVCenter
                            radius: 20
                            color: card.isSelected ? Qt.rgba(207/255, 188/255, 255/255, 0.12)
                                                   : root.colSurfaceHigh

                            Behavior on color { ColorAnimation { duration: 180 } }

                            Text {
                                anchors.centerIn: parent
                                text: modelData.icon
                                font.family: "Material Symbols Rounded"
                                font.pixelSize: 40
                                font.variableAxes: ({
                                    "FILL": card.isSelected ? 1 : 0,
                                    "opsz": 40
                                })
                                color: card.isSelected ? root.colPrimary : root.colOnSurfaceVar
                                renderType: Text.NativeRendering
                                Behavior on color { ColorAnimation { duration: 180 } }
                            }
                        }

                        Item { width: 24 }

                        /* Title + description */
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 4

                            Text {
                                text: modelData.title
                                font.pixelSize: 17
                                font.weight: Font.Medium
                                color: card.isSelected ? root.colOnSecCont : root.colOnSurface
                                renderType: Text.NativeRendering
                            }
                            Text {
                                Layout.fillWidth: true
                                text: modelData.desc
                                font.pixelSize: 13
                                color: card.isSelected ? root.colOnSecCont : root.colOnSurfaceVar
                                wrapMode: Text.WordWrap
                                lineHeight: 1.3
                                renderType: Text.NativeRendering
                            }
                        }
                    }
                }
            }

            /* Spacer */
            Item { Layout.fillHeight: true }
        }
    }


    /* ═════════════════════════════════════════════════════════════════════════
       PAGE 2 — PACKAGE SELECTION (Customize only)
       ═════════════════════════════════════════════════════════════════════════ */
    Item {
        id: packagePage
        anchors.fill: parent
        visible: root.currentPage === 1

        ColumnLayout {
            anchors.fill: parent
            anchors.topMargin: 14
            anchors.bottomMargin: 8
            spacing: 0

            /* Title */
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "Select Your Apps"
                font.pixelSize: 24
                font.weight: Font.Medium
                color: root.colOnSurface
                renderType: Text.NativeRendering
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 4
                Layout.bottomMargin: 16
                text: "Check the apps you want to install. The Included Extras are pre-selected."
                font.pixelSize: 14
                color: root.colOnSurfaceVar
                renderType: Text.NativeRendering
            }

            /* ── Scrollable package tree ──────────────────────────────── */
            Flickable {
                id: pkgFlick
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: pkgColumn.height
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ScrollBar.vertical: ScrollBar {
                    width: 8
                    policy: ScrollBar.AsNeeded
                    contentItem: Rectangle {
                        implicitWidth: 8
                        radius: 4
                        color: root.colOutlineVar
                    }
                }

                Column {
                    id: pkgColumn
                    width: pkgFlick.width
                    spacing: 6

                    Repeater {
                        model: root.packageGroups.length

                        delegate: Column {
                            id: groupDel
                            width: pkgColumn.width

                            readonly property int gIdx: index
                            readonly property var group: root.packageGroups[index]
                            readonly property bool expanded: !!root.groupExpanded[index]
                            readonly property int checkedCount: root.groupCheckedCount(index)
                            readonly property int totalCount: group.packages.length

                            /* ── Group header ─────────────────────────── */
                            Rectangle {
                                width: parent.width
                                height: 48
                                radius: expanded && checkedCount > 0 ? 12 : 12
                                color: root.colSurfaceCont

                                Behavior on color { ColorAnimation { duration: 120 } }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.toggleExpand(groupDel.gIdx)
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 14
                                    spacing: 10

                                    /* Group checkbox */
                                    Rectangle {
                                        Layout.preferredWidth: 20
                                        Layout.preferredHeight: 20
                                        Layout.alignment: Qt.AlignVCenter
                                        radius: 4
                                        color: groupDel.checkedCount === groupDel.totalCount
                                               ? root.colPrimary
                                               : groupDel.checkedCount > 0
                                                 ? root.colSecCont : "transparent"
                                        border.width: 2
                                        border.color: groupDel.checkedCount > 0
                                                      ? root.colPrimary : root.colOutline

                                        Text {
                                            anchors.centerIn: parent
                                            text: groupDel.checkedCount === groupDel.totalCount
                                                  ? "check" : "remove"
                                            font.family: "Material Symbols Rounded"
                                            font.pixelSize: 16
                                            font.variableAxes: ({ "FILL": 1, "opsz": 16 })
                                            color: groupDel.checkedCount === groupDel.totalCount
                                                   ? "#141218" : root.colOnSecCont
                                            visible: groupDel.checkedCount > 0
                                            renderType: Text.NativeRendering
                                        }

                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.toggleGroup(groupDel.gIdx)
                                        }
                                    }

                                    /* Group icon */
                                    Text {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: groupDel.group.icon
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: 20
                                        font.variableAxes: ({ "FILL": 1, "opsz": 20 })
                                        color: root.colOnSurfaceVar
                                        renderType: Text.NativeRendering
                                    }

                                    /* Group name */
                                    Text {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        text: groupDel.group.name
                                        font.pixelSize: 14
                                        font.weight: Font.Medium
                                        color: root.colOnSurface
                                        renderType: Text.NativeRendering
                                    }

                                    /* Package count badge */
                                    Text {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: groupDel.checkedCount + " / " + groupDel.totalCount
                                        font.pixelSize: 12
                                        color: root.colOutline
                                        renderType: Text.NativeRendering
                                    }

                                    /* Expand/collapse arrow */
                                    Text {
                                        Layout.alignment: Qt.AlignVCenter
                                        text: groupDel.expanded ? "expand_less" : "expand_more"
                                        font.family: "Material Symbols Rounded"
                                        font.pixelSize: 22
                                        font.variableAxes: ({ "FILL": 0, "opsz": 22 })
                                        color: root.colOnSurfaceVar
                                        renderType: Text.NativeRendering
                                    }
                                }
                            }

                            /* ── Expanded package list ────────────────── */
                            Column {
                                width: parent.width
                                visible: groupDel.expanded
                                topPadding: 2
                                bottomPadding: 6

                                Repeater {
                                    model: groupDel.group.packages.length

                                    delegate: Rectangle {
                                        id: pkgRow
                                        width: groupDel.width
                                        height: 38
                                        color: pkgMa.containsMouse ? root.colSurfaceHigh : "transparent"
                                        radius: 8

                                        readonly property int pIdx: index
                                        readonly property var pkg: groupDel.group.packages[index]
                                        readonly property bool isChecked:
                                            !!root.pkgChecked[groupDel.gIdx + ":" + index]

                                        Behavior on color { ColorAnimation { duration: 100 } }

                                        MouseArea {
                                            id: pkgMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.togglePkg(groupDel.gIdx, pkgRow.pIdx)
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 48
                                            anchors.rightMargin: 14
                                            spacing: 10

                                            /* Package checkbox */
                                            Rectangle {
                                                Layout.preferredWidth: 18
                                                Layout.preferredHeight: 18
                                                Layout.alignment: Qt.AlignVCenter
                                                radius: 4
                                                color: pkgRow.isChecked ? root.colPrimary : "transparent"
                                                border.width: 2
                                                border.color: pkgRow.isChecked
                                                              ? root.colPrimary : root.colOutline

                                                Text {
                                                    anchors.centerIn: parent
                                                    text: "check"
                                                    font.family: "Material Symbols Rounded"
                                                    font.pixelSize: 14
                                                    font.variableAxes: ({ "FILL": 1, "opsz": 14 })
                                                    color: "#141218"
                                                    visible: pkgRow.isChecked
                                                    renderType: Text.NativeRendering
                                                }
                                            }

                                            /* Package name */
                                            Text {
                                                Layout.preferredWidth: 200
                                                Layout.alignment: Qt.AlignVCenter
                                                text: pkgRow.pkg.name
                                                font.pixelSize: 13
                                                font.weight: Font.Medium
                                                color: root.colOnSurface
                                                elide: Text.ElideRight
                                                renderType: Text.NativeRendering
                                            }

                                            /* Description */
                                            Text {
                                                Layout.fillWidth: true
                                                Layout.alignment: Qt.AlignVCenter
                                                text: pkgRow.pkg.desc
                                                font.pixelSize: 12
                                                color: root.colOnSurfaceVar
                                                elide: Text.ElideRight
                                                renderType: Text.NativeRendering
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
