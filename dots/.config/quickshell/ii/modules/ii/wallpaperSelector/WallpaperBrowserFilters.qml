import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * Search filters of the wallpaper browser tab, adapted to the active source.
 * Opened from the tune button of ExtraOptionsToolbar. Every control writes straight
 * to Config.options.wallpapers (or the keyring for API keys); the last search is
 * re-run when the popup closes.
 */
Popup {
    id: root

    readonly property string provider: WallpaperBrowser.currentProvider
    readonly property bool isWallhaven: provider === "wallhaven"
    readonly property bool isCatalog: provider === "blapples" || provider === "naive"
    readonly property var wp: Config.options.wallpapers
    readonly property string providerName: WallpaperBrowser.providers[provider]?.name ?? provider
    readonly property string keyName: provider === "wallhaven" ? "wallhaven" : provider === "pexels" ? "pexels" : "wallpapers_unsplash"
    readonly property string keyValue: KeyringStorage.keyringData?.apiKeys?.[keyName] ?? ""
    readonly property string sortKey: WallpaperBrowser.currentSortType === "favourites" ? "favorites" : WallpaperBrowser.currentSortType
    readonly property var sortOptions: isWallhaven ? [
        { key: "date_added", name: Translation.tr("Latest") },
        { key: "relevance",  name: Translation.tr("Relevance") },
        { key: "random",     name: Translation.tr("Random") },
        { key: "views",      name: Translation.tr("Views") },
        { key: "favorites",  name: Translation.tr("Favorites") },
        { key: "toplist",    name: Translation.tr("Top list") },
        { key: "hot",        name: Translation.tr("Hot") },
    ] : provider === "unsplash" ? [
        { key: "relevant", name: Translation.tr("Relevance") },
        { key: "latest",   name: Translation.tr("Latest") },
    ] : []

    property bool dirty: false

    function toggleDigit(value, index) {
        const chars = String(value).padEnd(3, "0").split("");
        chars[index] = chars[index] === "1" ? "0" : "1";
        return chars.join("");
    }

    function rerunSearch() {
        const tags = Array.from(WallpaperBrowser.currentSearchTags || []);
        if (tags.length === 0 && WallpaperBrowser.responses.length === 0) return;
        const similarId = WallpaperBrowser.similarImageId;
        WallpaperBrowser.clearResponses();
        if (similarId !== "") WallpaperBrowser.moreLikeThisPicture(similarId, 1);
        else WallpaperBrowser.makeRequest(tags, 20, 1);
    }

    modal: false
    focus: true
    padding: 16
    width: 360
    x: parent ? (parent.width - width) / 2 + 160 : 0
    y: -height - 12
    transformOrigin: Popup.Bottom
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
    onClosed: {
        if (dirty) {
            dirty = false;
            rerunSearch();
        }
    }

    enter: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 160; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: 200; easing.type: Easing.OutCubic }
        }
    }
    exit: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 110; easing.type: Easing.InCubic }
            NumberAnimation { property: "scale"; from: 1; to: 0.96; duration: 110; easing.type: Easing.InCubic }
        }
    }

    background: Rectangle {
        radius: Appearance.rounding.normal
        color: Appearance.m3colors.m3surfaceContainer
        border.width: 1
        border.color: Appearance.colors.colLayer0Border
    }

    contentItem: Loader {
        active: true
        sourceComponent: bodyComponent
    }

    component FilterLabel: StyledText {
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colSubtext
    }

    component FilterChip: RippleButton {
        id: chip
        property string label: ""
        property color activeColor: Appearance.colors.colPrimary
        implicitHeight: 32
        buttonRadius: height / 2
        leftPadding: 14
        rightPadding: 14
        colBackgroundToggled: activeColor
        contentItem: StyledText {
            text: chip.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: chip.toggled ? Appearance.colors.colOnPrimary : Appearance.colors.colOnLayer1
        }
    }

    Component {
        id: bodyComponent

        ColumnLayout {
            width: root.availableWidth
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                MaterialSymbol {
                    text: "tune"
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colPrimary
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.providerName
                    font.pixelSize: Appearance.font.pixelSize.large
                }
            }

            // Sort
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: root.sortOptions.length > 0
                FilterLabel { text: Translation.tr("Sort by") }
                StyledComboBox {
                    Layout.fillWidth: true
                    model: root.sortOptions.map(o => o.name)
                    currentIndex: Math.max(0, root.sortOptions.findIndex(o => o.key === root.sortKey))
                    onCurrentIndexChanged: {
                        if (!root.visible || currentIndex < 0) return;
                        const key = root.sortOptions[currentIndex].key;
                        if (key === root.sortKey) return;
                        WallpaperBrowser.setSort(key);
                        root.dirty = true;
                    }
                }
            }

            // Top range (wallhaven toplist only)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: root.isWallhaven && root.sortKey === "toplist"
                FilterLabel { text: Translation.tr("Top range") }
                StyledComboBox {
                    Layout.fillWidth: true
                    property var keys: ["1d", "3d", "1w", "1M", "3M", "6M", "1y"]
                    model: [Translation.tr("1 day"), Translation.tr("3 days"), Translation.tr("1 week"), Translation.tr("1 month"), Translation.tr("3 months"), Translation.tr("6 months"), Translation.tr("1 year")]
                    currentIndex: Math.max(0, keys.indexOf(root.wp.wallhavenTopRange))
                    onCurrentIndexChanged: {
                        if (!root.visible || currentIndex < 0) return;
                        if (keys[currentIndex] === root.wp.wallhavenTopRange) return;
                        root.wp.wallhavenTopRange = keys[currentIndex];
                        root.dirty = true;
                    }
                }
            }

            // Order (wallhaven)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: root.isWallhaven && root.sortKey !== "random"
                FilterLabel { text: Translation.tr("Order") }
                StyledComboBox {
                    Layout.fillWidth: true
                    property var keys: ["desc", "asc"]
                    model: [Translation.tr("Descending"), Translation.tr("Ascending")]
                    currentIndex: Math.max(0, keys.indexOf(root.wp.wallhavenOrder))
                    onCurrentIndexChanged: {
                        if (!root.visible || currentIndex < 0) return;
                        if (keys[currentIndex] === root.wp.wallhavenOrder) return;
                        root.wp.wallhavenOrder = keys[currentIndex];
                        root.dirty = true;
                    }
                }
            }

            // Ratio (wallhaven)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: root.isWallhaven
                FilterLabel { text: Translation.tr("Ratio") }
                StyledComboBox {
                    Layout.fillWidth: true
                    property var keys: ["", "16x9", "16x10", "21x9", "32x9", "9x16", "10x16", "1x1", "3x2", "4x3", "5x4"]
                    model: [Translation.tr("Any"), "16x9", "16x10", "21x9", "32x9", "9x16", "10x16", "1x1", "3x2", "4x3", "5x4"]
                    currentIndex: Math.max(0, keys.indexOf(root.wp.wallhavenRatios))
                    onCurrentIndexChanged: {
                        if (!root.visible || currentIndex < 0) return;
                        if (keys[currentIndex] === root.wp.wallhavenRatios) return;
                        root.wp.wallhavenRatios = keys[currentIndex];
                        root.dirty = true;
                    }
                }
            }


            // Categories (wallhaven)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: root.isWallhaven
                FilterLabel { text: Translation.tr("Categories") }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [Translation.tr("General"), Translation.tr("Anime"), Translation.tr("People")]
                        delegate: FilterChip {
                            required property int index
                            required property string modelData
                            label: modelData
                            toggled: WallpaperBrowser.wallhavenCategories.charAt(index) === "1"
                            onClicked: {
                                const n = root.toggleDigit(WallpaperBrowser.wallhavenCategories, index);
                                if (n === "000") return;
                                root.wp.wallhavenCategories = n;
                                root.dirty = true;
                            }
                        }
                    }
                }
            }

            // Purity (wallhaven)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: root.isWallhaven
                FilterLabel { text: Translation.tr("Purity") }
                Flow {
                    Layout.fillWidth: true
                    spacing: 6
                    Repeater {
                        model: [
                            { name: "SFW", needsKey: false },
                            { name: Translation.tr("Sketchy"), needsKey: false },
                            { name: "NSFW", needsKey: true },
                        ]
                        delegate: FilterChip {
                            required property int index
                            required property var modelData
                            visible: !modelData.needsKey || WallpaperBrowser.wallhavenApiToken.length > 0
                            label: modelData.name
                            activeColor: modelData.needsKey ? Appearance.m3colors.m3error : Appearance.colors.colPrimary
                            toggled: WallpaperBrowser.wallhavenPurityValue.charAt(index) === "1"
                            onClicked: {
                                const n = root.toggleDigit(WallpaperBrowser.wallhavenPurityValue, index);
                                if (n === "000") return;
                                root.wp.wallhavenPurity = n;
                                root.dirty = true;
                            }
                        }
                    }
                }
            }

            // Colour (wallhaven and the catalogs)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 4
                visible: root.isWallhaven || root.isCatalog
                FilterLabel { text: Translation.tr("Colour") }
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: ["Red", "Orange", "Yellow", "Green", "Blue", "Purple"]
                        delegate: Rectangle {
                            id: swatch
                            required property string modelData
                            readonly property bool picked: WallpaperBrowser.colorFilter === modelData
                            width: 28
                            height: 28
                            radius: 14
                            color: "#" + WallpaperBrowser.colorHex[modelData]
                            border.width: picked ? 3 : 1
                            border.color: picked ? Appearance.colors.colOnLayer1 : Appearance.colors.colLayer0Border
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    WallpaperBrowser.colorFilter = swatch.picked ? "" : swatch.modelData;
                                    root.dirty = true;
                                }
                            }
                        }
                    }
                }
            }

            StyledText {
                visible: root.provider === "pexels"
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: Translation.tr("Landscape photos only. A key is required to search.")
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
            }

            // API key
            ColumnLayout {
                Layout.fillWidth: true
                visible: !root.isCatalog
                spacing: 4
                FilterLabel { text: Translation.tr("API key") }
                TextField {
                    id: apiKeyField
                    Layout.fillWidth: true
                    echoMode: TextInput.Password
                    placeholderText: root.isWallhaven ? Translation.tr("Optional, needed for NSFW") : Translation.tr("Required for this source")
                    placeholderTextColor: Appearance.colors.colSubtext
                    color: Appearance.colors.colOnLayer1
                    text: root.keyValue
                    font.pixelSize: Appearance.font.pixelSize.small
                    background: Rectangle {
                        color: Appearance.colors.colLayer1
                        radius: Appearance.rounding.small
                        border.width: 1
                        border.color: apiKeyField.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
                    }
                    onEditingFinished: {
                        const v = text.trim();
                        if (v === root.keyValue) return;
                        KeyringStorage.setNestedField(["apiKeys", root.keyName], v);
                        root.dirty = true;
                    }
                }
            }
        }
    }
}
