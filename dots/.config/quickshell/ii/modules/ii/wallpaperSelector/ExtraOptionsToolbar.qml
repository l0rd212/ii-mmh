import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Toolbar {
    id: extraOptions
    z: 20
    padding: 6
    spacing: 6
    colBackground: Appearance.m3colors.m3surfaceContainerLow

    property string text: filterField.text
    property alias searchField: filterField
    signal closeRequested

    function switchSource(provider) {
        const tags = Array.from(WallpaperBrowser.currentSearchTags || []);
        const keepSimilar = WallpaperBrowser.similarImageId !== "";
        const hadResults = WallpaperBrowser.responses.length > 0;
        Config.options.wallpapers.service = provider;
        if (provider === "unsplash") Config.options.wallpapers.sort = "relevant";
        else if (provider === "wallhaven") Config.options.wallpapers.sort = "favorites";
        WallpaperBrowser.clearResponses();
        if ((tags.length > 0 || ["blapples", "naive"].includes(provider) || (hadResults && ["wallhaven", "pexels", "blapples", "naive"].includes(provider))) && !keepSimilar) WallpaperBrowser.makeRequest(tags, 20, 1);
    }

    function focusSearch() {
        filterField.forceActiveFocus();
        filterField.cursorPosition = filterField.text.length;
    }

    function setSearchText(value) {
        filterField.text = value;
        filterField.cursorPosition = filterField.text.length;
    }

    function clearSearch() {
        setSearchText("");
    }

    WallpaperBrowserFilters {
        id: filtersPopup
    }

    StyledComboBox {
        id: sourceCombo
        visible: wallpaperSelectorContent.browserMode
        implicitWidth: 140
        model: WallpaperBrowser.providerList.map(p => WallpaperBrowser.providers[p].name)
        currentIndex: Math.max(0, WallpaperBrowser.providerList.indexOf(WallpaperBrowser.currentProvider))
        onCurrentIndexChanged: {
            if (!visible || currentIndex < 0) return;
            const p = WallpaperBrowser.providerList[currentIndex];
            if (p === WallpaperBrowser.currentProvider) return;
            extraOptions.switchSource(p);
        }
    }

    ToolbarTextField {
        id: filterField
        implicitWidth: Appearance.sizes.wallpaperSelectorSearchWidth
        colBackground: Appearance.colors.colLayer2
        placeholderText: {
            if (wallpaperSelectorContent.browserMode) return Translation.tr("Search API (e.g. nature, city)");
            return focus ? Translation.tr("Search wallpapers") : Translation.tr("Hit \"/\" to search")
        }

        // Style
        clip: true
        font.pixelSize: Appearance.font.pixelSize.small

        // Search
        onTextChanged: {
            if (!wallpaperSelectorContent.browserMode) {
                Wallpapers.searchQuery = text;
                if (wallpaperSelectorContent.favMode) {
                    wallpaperSelectorContent.refreshFavourites();
                }
            }
        }

        // The floating pill only owns the keyboard when it is on screen: the
        // compact layout keeps this toolbar hidden and draws its own search in the
        // address row, which would otherwise lose the focus to this invisible field.
        Component.onCompleted: if (extraOptions.visible) extraOptions.focusSearch()

        onAccepted: {
            if (wallpaperSelectorContent.browserMode && (text.trim().length > 0 || ["wallhaven", "pexels", "blapples", "naive"].includes(WallpaperBrowser.currentProvider))) {
                const newTags = text.trim().split(/\s+/).filter(w => w.length > 0);
                const allTags = [...newTags];
                wallpaperSelectorContent.moreOptionsModelData = null
                WallpaperBrowser.clearResponses();
                WallpaperBrowser.makeRequest(allTags, 20, 1);
                wallpaperSelectorContent.view.currentIndex = 0;
                text = "";
            } else if (!wallpaperSelectorContent.browserMode && wallpaperSelectorContent.view.count > 0) {
                // TextInput owns the focus while searching, so forward Enter
                // explicitly to the same activation path used by the shell.
                wallpaperSelectorContent.view.activateCurrent();
            }
        }

        Keys.onPressed: event => {
            if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) { // Intercept Ctrl+V to handle "paste to go to" in pickers
                wallpaperSelectorContent.handleFilePasting(event);
                return;
            }
            else if (text.length !== 0) {
                // No filtering, just navigate grid
                if (event.key === Qt.Key_Down) {
                    wallpaperSelectorContent.view.moveSelection(wallpaperSelectorContent.compact ? 1 : grid.columns);
                    event.accepted = true;
                    return;
                }
                if (event.key === Qt.Key_Up) {
                    wallpaperSelectorContent.view.moveSelection(wallpaperSelectorContent.compact ? -1 : -grid.columns);
                    event.accepted = true;
                    return;
                }
            }
            event.accepted = false;
        }
    }

    IconToolbarButton {
        id: prevPageButton
        visible: wallpaperSelectorContent.browserMode && WallpaperBrowser.responses.length > 0
        enabled: WallpaperBrowser.currentPage > 1 && WallpaperBrowser.runningRequests === 0
        implicitWidth: height
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colBackgroundActive: Appearance.colors.colLayer2Active
        colText: Appearance.colors.colOnLayer2
        colRipple: Appearance.colors.colLayer2Active
        onClicked: WallpaperBrowser.goToPage(WallpaperBrowser.currentPage - 1)
        text: "chevron_left"
        StyledToolTip {
            text: Translation.tr("Previous page")
        }
    }

    StyledText {
        visible: wallpaperSelectorContent.browserMode && WallpaperBrowser.responses.length > 0
        text: WallpaperBrowser.currentPage.toString()
        color: Appearance.colors.colOnLayer2
        font.pixelSize: Appearance.font.pixelSize.small
        horizontalAlignment: Text.AlignHCenter
    }

    IconToolbarButton {
        id: nextPageButton
        visible: wallpaperSelectorContent.browserMode && WallpaperBrowser.responses.length > 0
        enabled: WallpaperBrowser.runningRequests === 0
        implicitWidth: height
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colBackgroundActive: Appearance.colors.colLayer2Active
        colText: Appearance.colors.colOnLayer2
        colRipple: Appearance.colors.colLayer2Active
        onClicked: WallpaperBrowser.goToPage(WallpaperBrowser.currentPage + 1)
        text: "chevron_right"
        StyledToolTip {
            text: Translation.tr("Next page")
        }
    }

    IconToolbarButton {
        id: tuneButton
        visible: wallpaperSelectorContent.browserMode
        implicitWidth: height
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colBackgroundActive: Appearance.colors.colLayer2Active
        colBackgroundToggled: Appearance.colors.colPrimary
        colBackgroundToggledHover: Appearance.colors.colPrimaryHover
        colBackgroundToggledActive: Appearance.colors.colPrimaryActive
        colText: Appearance.colors.colOnLayer2
        colRipple: Appearance.colors.colLayer2Active
        colRippleToggled: Appearance.colors.colPrimaryActive
        toggled: filtersPopup.opened
        onClicked: filtersPopup.opened ? filtersPopup.close() : filtersPopup.open()
        text: "tune"
        StyledToolTip {
            text: Translation.tr("Search filters")
        }
    }

    IconToolbarButton {
        implicitWidth: height
        colBackground: Appearance.colors.colLayer2
        colBackgroundHover: Appearance.colors.colLayer2Hover
        colBackgroundActive: Appearance.colors.colLayer2Active
        colBackgroundToggled: Appearance.colors.colPrimary
        colBackgroundToggledHover: Appearance.colors.colPrimaryHover
        colBackgroundToggledActive: Appearance.colors.colPrimaryActive
        colText: Appearance.colors.colOnLayer2
        colRipple: Appearance.colors.colLayer2Active
        colRippleToggled: Appearance.colors.colPrimaryActive
        downAction: () => extraOptions.closeRequested()
        onClicked: extraOptions.closeRequested()
        text: "close"
        StyledToolTip {
            text: Translation.tr("Cancel wallpaper selection")
        }
    }                        
}
