pragma Singleton  
pragma ComponentBehavior: Bound  
  
import qs.modules.common  
import qs.services  
import Quickshell;
import Quickshell.Io  
import QtQuick;  
  
/**  
 * A service for interacting with wallpaper APIs (Unsplash and Wallhaven).  
 */  
Singleton {  
    id: root  
    property Component unsplashResponseDataComponent: WallpaperResponseData {}  
  
    signal tagSuggestion(string query, var suggestions)  
    signal responseFinished()  
  
    property string unsplashApiToken: KeyringStorage.keyringData?.apiKeys?.wallpapers_unsplash ?? ""
    property string pexelsApiToken: KeyringStorage.keyringData?.apiKeys?.pexels ?? ""
    property string wallhavenApiToken: KeyringStorage.keyringData?.apiKeys?.wallhaven ?? ""
    property string failMessage: Translation.tr("That didn't work. Tips:\n- Check your search query\n- Try different keywords\n- Check your API key under settings")  
    property var responses: []
    property int runningRequests: 0
    property string errorMessage: ""
    property int currentPage: 1
    property var providerList: ["unsplash", "wallhaven", "pexels", "blapples", "naive"]  
    property var currentProvider: Config.options.wallpapers.service ?? "wallhaven" // defaulting to wallhaven bc it doesnt require api key

    property string currentSortType: Config.options.wallpapers.sort ?? "favourites" // Options for wallhaven: date_added, relevance, random, views, favourites, toplist // Options for unsplash: relevant, latest
    property bool showAnimeResults: Config.options.wallpapers.showAnimeResults ?? false
    // Wallhaven filters, set in Config.options.wallpapers.wallhaven*
    property string wallhavenCategories: Config.options.wallpapers.wallhavenCategories || (showAnimeResults ? "110" : "100")
    property string wallhavenPurityValue: {
        const p = Config.options.wallpapers.wallhavenPurity;
        if (wallhavenApiToken === "") {
            const q = (p && p !== "auto") ? p.substring(0, 2) + "0" : "100"; // NSFW needs an API key
            return q === "000" ? "100" : q;
        }
        return (p && p !== "auto") ? p : "100";
    }
    property string wallhavenMinResolution: Config.options.wallpapers.wallhavenMinResolution || "1920x1080"
    property string wallhavenRatios: Config.options.wallpapers.wallhavenRatios || ""

    property string similarImageId: ""
    property var currentSearchTags: []
    
    property var providers: {  
        "system": { "name": Translation.tr("System") },
        "blapples": { "name": "Blapples", "url": "https://github.com/Blapples/wallpapers", "description": Translation.tr("Curated anime wallpapers (no key needed)") },
        "naive": { "name": "NA-ive", "url": "https://github.com/na-ive/wallpapers", "description": Translation.tr("Curated wallpapers (no key needed)") },
        "pexels": {
            "name": "Pexels",
            "url": "https://www.pexels.com",
            "api": "https://api.pexels.com/v1/search",
            "description": Translation.tr("Free photos from Pexels"),
            "mapFunc": (response) => {
                const items = Array.isArray(response.photos) ? response.photos : [];
                return items.map(item => {
                    return {
                        "id": String(item.id),
                        "width": item.width,
                        "height": item.height,
                        "aspect_ratio": item.width / item.height,
                        "tags": item.alt || "wallpaper",
                        "rating": "s",
                        "is_nsfw": false,
                        "md5": String(item.id),
                        "preview_url": item.src.medium,
                        "sample_url": item.src.large,
                        "file_url": item.src.original + "?auto=compress&cs=tinysrgb&w=2560&h=1440&fit=crop",
                        "file_ext": "jpg",
                        "source": item.url,
                        "author": item.photographer,
                        "author_url": item.photographer_url,
                        "color": item.avg_color || ""
                    }
                })
            }
        },  
        "unsplash": {  
            "name": "Unsplash",  
            "url": "https://unsplash.com",  
            "api": "https://api.unsplash.com/search/photos",            
            "description": Translation.tr("High quality photos from Unsplash"),  
            "mapFunc": (response) => {  
                const items = Array.isArray(response.results) ? response.results : [];
                return items.map(item => {  
                    return {  
                        "id": item.id,  
                        "width": item.width,  
                        "height": item.height,  
                        "aspect_ratio": item.width / item.height,  
                        "tags": item.tags ? item.tags.map(tag => tag.title).join(" ") : (item.alt_description || item.description || "wallpaper"),  
                        "rating": "s",  
                        "is_nsfw": false,  
                        "md5": item.id,  
                        "preview_url": item.urls.small,  
                        "sample_url": item.urls.full,  
                        "file_url": item.urls.full,  
                        "file_ext": "jpg",  
                        "source": item.links.html,  
                        "author": item.user.name,  
                        "author_url": item.user.links.html,
                        "color": item.color || ""
                    }  
                })  
            },  
            "tagSearchTemplate": "https://api.unsplash.com/search/collections",  
            "tagMapFunc": (response) => {  
                return response.results.slice(0, 10).map(item => {  
                    return {  
                        "name": item.title.toLowerCase().replace(/\s+/g, '-'),  
                        "displayName": item.title,  
                        "count": item.total_photos,  
                        "description": item.description || ""  
                    }  
                })  
            }  
        },  
        "wallhaven": {  
            "name": "Wallhaven",  
            "url": "https://wallhaven.cc",  
            "api": "https://wallhaven.cc/api/v1/search",  
            "description": Translation.tr("Wallpapers | Advanced search with ratios, resolutions, categories, sorting"),  
            "mapFunc": (response) => {  
                console.log("[Wallpapers] Wallhaven response structure: " + JSON.stringify(Object.keys(response)))  
                if (!response.data) {  
                    console.log("[Wallpapers] Wallhaven response has no data field")  
                    return [];  
                }  
                if (!Array.isArray(response.data)) {  
                    console.log("[Wallpapers] Wallhaven response.data is not an array: " + typeof response.data)  
                    return [];  
                }  
                console.log("[Wallpapers] Wallhaven found " + response.data.length + " items")  
                response = response.data  
                return response.map(item => {  
                    return {  
                        "id": item.id,  
                        "width": item.dimension_x || 1920,  
                        "height": item.dimension_y || 1080,  
                        "aspect_ratio": (item.dimension_x || 1920) / (item.dimension_y || 1080),  
                        "tags": item.tags && Array.isArray(item.tags) ? item.tags.map(tag => tag.name).join(" ") : "",  
                        "rating": item.purity === 'sfw' ? 's' : item.purity === 'sketchy' ? 'q' : 'e',  
                        "is_nsfw": item.purity !== 'sfw',  
                        "md5": item.id,  
                        "preview_url": item.thumbs && item.thumbs.original ? item.thumbs.original : item.path,  
                        "sample_url": item.thumbs && item.thumbs.small ? item.thumbs.small : item.path,  
                        "file_url": item.path,  
                        "file_ext": item.file_type ? item.file_type.split('/')[1] : 'jpg',  
                        "source": item.source || "",
                        "color": item.colors[0] || ""  
                    }  
                })  
            },  
            "tagSearchTemplate": "https://wallhaven.cc/api/v1/search",  
            "tagMapFunc": (response) => {  
                if (!response.data) return [];  
                return response.data.slice(0, 10).map(item => {  
                    return {  
                        "name": item.tags && item.tags.length > 0 ? item.tags[0].name : "",  
                        "count": ""  
                    }  
                })  
            }  
        }  
    }  

    function setSort(sort) {
        sort = sort.toLowerCase() 
        Config.options.wallpapers.sort = sort
    }

    function setAnimeResults(show) {
        Config.options.wallpapers.showAnimeResults = show
    }
  
    function setProvider(provider) {  
        provider = provider.toLowerCase()  
        if (providerList.indexOf(provider) !== -1) {  
            Config.options.wallpapers.service = provider
            root.addSystemMessage(Translation.tr("Provider set to ") + providers[provider].name) 
            if (provider === "unsplash") {
                root.currentSortType = "relevance" // default value
            } 
            if (provider === "wallhaven") {
                root.currentSortType = "favourites" // default value
            }
        } else {  
            root.addSystemMessage(Translation.tr("Invalid API provider. Supported: \n- ") + providerList.join("\n- "))  
        }  
    }  
  
    // ─── Download a remote wallpaper into the download folder, then apply it ───
    property string downloadingUrl: ""

    function downloadAndApply(url, darkMode, applyAfter = true) {
        if (downloadProc.running) return;
        const cleanUrl = String(url).split(/[?#]/)[0];
        const rawName = decodeURIComponent(cleanUrl.substring(cleanUrl.lastIndexOf("/") + 1));
        const m = rawName.match(/\.([a-z0-9]{2,5})$/i);
        const allowed = ["jpg", "jpeg", "png", "webp", "avif", "bmp"];
        const ext = (m && allowed.includes(m[1].toLowerCase())) ? m[1].toLowerCase() : "jpg";
        const stem = (m ? rawName.slice(0, rawName.length - m[0].length) : rawName)
            .replace(/[^a-zA-Z0-9._-]/g, "_").replace(/^[-_.]+/, "").slice(0, 80) || "wallpaper";
        const dir = (String(Config.options?.wallpapers?.paths?.download || "").replace(/^file:\/\//, "") || `${Directories.pictures}/Wallpapers`).replace(/\/+$/, "");
        const target = `${dir}/${stem}.${ext}`;
        downloadProc.target = target;
        downloadProc.dark = darkMode;
        downloadProc.applyAfter = applyAfter;
        root.downloadingUrl = url;
        downloadProc.command = ["bash", "-c",
            'mkdir -p -- "$1" && { [ -s "$2" ] || { curl -fL --retry 2 --connect-timeout 10 --remove-on-error --output "$3" "$4" && mv -f -- "$3" "$2"; }; }',
            "dl", dir, target, target + ".part", url];
        downloadProc.running = true;
    }

    Process {
        id: downloadProc
        property string target: ""
        property bool dark: true
        property bool applyAfter: true
        onExited: (exitCode) => {
            root.downloadingUrl = "";
            if (exitCode === 0) {
                Quickshell.execDetached(["notify-send", "-a", "Shell", Translation.tr("Download complete"), downloadProc.target]);
                if (downloadProc.applyAfter) Wallpapers.select(downloadProc.target, downloadProc.dark);
            } else {
                root.errorMessage = Translation.tr("Download failed. Check the network or download folder.");
                Quickshell.execDetached(["notify-send", "-a", "Shell", Translation.tr("Download failed"), downloadProc.target]);
            }
        }
    }

    function goToPage(page) {
        if (page < 1 || root.runningRequests > 0) return;
        const tags = Array.from(root.currentSearchTags || []);
        const similarId = root.similarImageId;
        root.responses = [];
        root.errorMessage = "";
        if (similarId !== "") root.makeRequest([], 20, page, similarId);
        else root.makeRequest(tags, 20, page);
    }

    function clearResponses() {  
        responses = []
        root.currentSearchTags = []
        root.errorMessage = ""
    }  
  
    function addSystemMessage(message) {  
        responses = [...responses, root.unsplashResponseDataComponent.createObject(null, {  
            "provider": "system",  
            "tags": [],  
            "page": -1,  
            "images": [],  
            "message": message  
        })]  
    }  

    function addSimilarImageMessage(message, fileUrl) {  
        responses = [...responses, root.unsplashResponseDataComponent.createObject(null, {  
            "provider": "system",  
            "tags": [],  
            "page": -1,  
            "images": [],  
            "message": message,
            "filePath": fileUrl
        })]  
    }  
  
    function constructRequestUrl(tags, limit=20, page=1, imageId="") {
        var provider = providers[currentProvider]  
        var baseUrl = provider.api  
        var url = baseUrl  
        var tagString = tags.join(" ")  
        var params = []  
          
         if (currentProvider === "unsplash") {
             if (tagString.trim().length > 0) {
                 params.push("query=" + encodeURIComponent(tagString))
             }
             params.push("per_page=" + Math.min(limit, 30))
             params.push("page=" + page)
             params.push(`order_by=${root.currentSortType}`)
             params.push("orientation=landscape")
         
             params.push("client_id=" + encodeURIComponent(root.unsplashApiToken))
         }

        else if (currentProvider === "pexels") {
            params.push("query=" + encodeURIComponent(tagString.trim().length > 0 ? tagString : "wallpaper"))
            params.push("orientation=landscape")
            params.push("size=large")
            params.push("per_page=" + limit)
            params.push("page=" + page)
        }
        else if (currentProvider === "wallhaven") {  
            if (imageId == "") {  // normal search

                const safeQuery = `${tagString}` // filter to not see people and faces
                if (tagString.trim().length > 0) {  
                    params.push("q=" + encodeURIComponent(safeQuery))  
                }  

                if (root.showAnimeResults) {
                    params.push("categories=" + root.wallhavenCategories)
                } else {
                    params.push("categories=" + root.wallhavenCategories)
                }
                
                params.push("purity=" + root.wallhavenPurityValue)
                params.push("page=" + page)
                params.push(`sorting=${root.currentSortType === "favourites" ? "favorites" : root.currentSortType}`)
                if (Config.options.wallpapers.wallhavenOrder && root.currentSortType !== "random") params.push("order=" + Config.options.wallpapers.wallhavenOrder)
                if (root.currentSortType === "toplist") params.push("topRange=" + (Config.options.wallpapers.wallhavenTopRange || "1y"))
                // no minimum resolution: small wallpapers can be upscaled
                if (root.wallhavenRatios !== "") params.push("ratios=" + root.wallhavenRatios)
                if (root.colorFilter !== "" && root.colorHex[root.colorFilter]) params.push("colors=" + root.colorHex[root.colorFilter])
                root.similarImageId = ""
            }

            if (imageId !== "") { // 'More like this picture' feature
                // console.log("[Wallpapers] Searching for more images like: " + imageId)

                params.push(`q=like%3A${imageId}`) // idk why but api has to be configured like this, learned it in the hard way
                params.push(`sorting=relevance`)
                params.push(`page=${page}`)
                params.push(`order=desc`)
                root.similarImageId = imageId
            }
        }  
          
        if (baseUrl.indexOf("?") === -1) {  
            url += "?" + params.join("&")  
        } else {  
            url += "&" + params.join("&")  
        }  
        return url  
    }  

    // ─── Static catalogs (Blapples, NA-ive): one JSON file, filtered and paged here ───
    property string colorFilter: ""
    readonly property var colorHex: ({ "Red": "cc0000", "Orange": "ff6600", "Yellow": "ffff00", "Green": "669900", "Blue": "0066cc", "Purple": "663399" })
    readonly property var catalogs: ({
        "blapples": {
            json: "https://raw.githubusercontent.com/Blapples/wallpapers/main/wallpapers.json",
            thumbBase: "https://raw.githubusercontent.com/Blapples/wallpapers/main/",
            fullBase: "https://raw.githubusercontent.com/Blapples/wallpapers/main/"
        },
        "naive": {
            json: "https://raw.githubusercontent.com/na-ive/wallpapers/gh-pages/wallpapers.json",
            thumbBase: "https://raw.githubusercontent.com/na-ive/wallpapers/gh-pages/",
            fullBase: "https://raw.githubusercontent.com/na-ive/wallpapers/main/"
        }
    })
    property var catalogCache: ({})

    function isCatalog(p) { return p === "blapples" || p === "naive"; }

    function encPath(p) { return String(p).split("/").map(encodeURIComponent).join("/"); }

    function mapCatalogItem(src, item) {
        const cfg = root.catalogs[src];
        const m = String(item.resolution || "").match(/(\d+)\s*x\s*(\d+)/i);
        const w = m ? parseInt(m[1]) : 1920, h = m ? parseInt(m[2]) : 1080;
        const fn = String(item.filename);
        const em = fn.match(/\.([a-z0-9]{2,5})$/i);
        const stem = fn.replace(/\.[^.]+$/, "");
        const groups = Array.isArray(item.color_groups) ? item.color_groups : [];
        return {
            "id": src + "-" + stem.slice(0, 40),
            "width": w, "height": h, "aspect_ratio": w / h,
            "tags": groups.join(" ") + " " + stem.replace(/[-_]+/g, " "),
            "rating": "s", "is_nsfw": false, "md5": src + "-" + stem,
            "preview_url": cfg.thumbBase + root.encPath(item.thumbnail || item.preview),
            "sample_url": cfg.thumbBase + root.encPath(item.preview || item.thumbnail),
            "file_url": cfg.fullBase + root.encPath(fn),
            "file_ext": em ? em[1].toLowerCase() : "jpg",
            "source": "", "color": item.color || ""
        };
    }

    function makeCatalogRequest(tags, limit, page) {
        const src = root.currentProvider;
        const cfg = root.catalogs[src];
        root.currentSearchTags = tags;
        root.errorMessage = "";
        root.currentPage = page;
        root.similarImageId = "";
        const newResponse = root.unsplashResponseDataComponent.createObject(null, {
            "provider": src, "tags": tags, "page": page, "images": [], "message": ""
        });
        const words = Array.from(tags).map(t => String(t).toLowerCase()).filter(t => t.length > 0);
        const finish = (list, ok) => {
            if (ok) {
                const sorted = list.slice().sort((a, b) => String(b.mtime || "").localeCompare(String(a.mtime || "")));
                const hits = sorted.filter(it => {
                    const groups = Array.isArray(it.color_groups) ? it.color_groups : [];
                    if (root.colorFilter !== "" && !groups.includes(root.colorFilter)) return false;
                    const hay = (String(it.filename) + " " + groups.join(" ")).toLowerCase();
                    return words.every(w => hay.indexOf(w) !== -1);
                });
                const items = hits.slice((page - 1) * limit, page * limit).map(it => root.mapCatalogItem(src, it));
                newResponse.images = items;
                newResponse.message = items.length > 0 ? "" : root.failMessage;
            } else {
                newResponse.message = root.failMessage;
                root.errorMessage = root.failMessage;
            }
            root.runningRequests = Math.max(0, root.runningRequests - 1);
            root.responses = [...root.responses, newResponse];
            root.responseFinished();
        };
        root.runningRequests++;
        if (root.catalogCache[src]) { finish(root.catalogCache[src], true); return; }
        const xhr = new XMLHttpRequest();
        xhr.open("GET", cfg.json);
        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return;
            if (xhr.status !== 200) { console.log("[Wallpapers] Catalog request failed: " + xhr.status); finish([], false); return; }
            try {
                let d = JSON.parse(xhr.responseText);
                if (!Array.isArray(d)) d = d.wallpapers || d.items || d.images || [];
                const cache = root.catalogCache; cache[src] = d; root.catalogCache = cache;
                finish(d, true);
            } catch (e) {
                console.log("[Wallpapers] Catalog parse error: " + e);
                finish([], false);
            }
        };
        xhr.send();
    }

    function moreLikeThisPicture(imageId, page=1) { // Uses built-in wallhaven's 'More like this picture' feature
        if (root.currentProvider !== "wallhaven") {
            root.addSystemMessage(Translation.tr("'More like this picture' feature only works with wallhaven service"))
            return;
        }
        root.currentSearchTags = [Translation.tr("Similar to ") + imageId]
        makeRequest([], 20, page, imageId)       
    }

    // Not used for now, but could be usefull in the future
    function getTags(imageId, callback) {
        if (currentProvider !== "wallhaven") {
            // console.log("[Wallpapers] getTags only works with wallhaven (for now, unsplash support will be added)")
            // root.addSystemMessage(Translation.tr("getTags only works with wallhaven (for now, unsplash support will be added)"))
            return;
        }
        
        var url = `https://wallhaven.cc/api/v1/w/${imageId}`
        // console.log("[Wallpapers] Fetching tags from " + url)
        
        var xhr = new XMLHttpRequest()
        xhr.open("GET", url)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
                try {
                    var response = JSON.parse(xhr.responseText)
                    if (response.data && response.data.tags) {
                        var tags = response.data.tags.map(tag => tag.name).join(" ")
                        // console.log("[Wallpapers] Tags for " + imageId + ": " + tags)
                        
                        if (callback && typeof callback === "function") {
                            callback(tags, response.data.tags)
                        }
                    }
                } catch (e) {
                    // console.log("[Wallpapers] Failed to parse tags response: " + e)
                    if (callback && typeof callback === "function") {
                        callback("", [])
                    }
                }
            }
            else if (xhr.readyState === XMLHttpRequest.DONE) {
                // console.log("[Wallpapers] getTags failed with status: " + xhr.status)
                if (callback && typeof callback === "function") {
                    callback("", [])
                }
            }
        }
        
        try {
            if (root.wallhavenApiToken) {
                xhr.setRequestHeader("X-API-Key", root.wallhavenApiToken)
            }
            xhr.send()
        } catch (error) {
            // console.log("[Wallpapers] Could not fetch tags:", error)
            if (callback && typeof callback === "function") {
                callback("", [])
            }
        }
    }
  
    function makeRequest(tags, limit=20, page=1, imageId="") {
        if (root.isCatalog(root.currentProvider)) { root.makeCatalogRequest(tags, limit, page); return; } // image id is used for "more like this" feature
        if (imageId === "") {
            root.currentSearchTags = tags;
        }
        root.errorMessage = "";
        root.currentPage = page;
        var url = constructRequestUrl(tags, limit, page, imageId)  
        console.log("[Wallpapers] Making request to " + url)  
  
        const newResponse = root.unsplashResponseDataComponent.createObject(null, {  
            "provider": currentProvider,  
            "tags": tags,  
            "page": page,  
            "images": [],  
            "message": ""
        })  
  
        var xhr = new XMLHttpRequest()  
        xhr.open("GET", url)  
        xhr.onreadystatechange = function() {  
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {  
                try {  
                    const provider = providers[currentProvider]  
                    let response = JSON.parse(xhr.responseText)  
                    response = provider.mapFunc(response)  

                    /* if (currentProvider === "wallhaven") { // can be used to set a limit to wallhaven (currently there is not), but not using it as it breaks the page sync
                        response = response.slice(0, limit)
                    } */

                    newResponse.images = response  
                    newResponse.message = response.length > 0 ? "" : root.failMessage
                      
                } catch (e) {  
                    console.log("[Wallpapers] Failed to parse response: " + e)  
                    newResponse.message = root.failMessage  
                    root.errorMessage = root.failMessage;
                } finally {  
                    root.runningRequests--;  
                    root.responses = [...root.responses, newResponse]  
                }  
            }  
            else if (xhr.readyState === XMLHttpRequest.DONE) {  
                console.log("[Wallpapers] Request failed with status: " + xhr.status)  
                newResponse.message = root.failMessage
                root.errorMessage = root.failMessage;
                root.runningRequests--;  
                root.responses = [...root.responses, newResponse]  
            }  
            root.responseFinished()  
        }  
  
        try {  
            if (currentProvider === "unsplash") {  
                xhr.setRequestHeader("Authorization", "Client-ID " + root.unsplashApiToken)  
            } else if (currentProvider === "pexels" && root.pexelsApiToken) {
                xhr.setRequestHeader("Authorization", root.pexelsApiToken)
            } else if (currentProvider === "wallhaven" && root.wallhavenApiToken) {  
                xhr.setRequestHeader("X-API-Key", root.wallhavenApiToken)  
            }  
            root.runningRequests++;  
            xhr.send()  
        } catch (error) {  
            console.log("Could not set headers:", error)  
            root.errorMessage = root.failMessage;
            root.runningRequests = Math.max(0, root.runningRequests - 1);
        }     
    }  
  
    property var currentTagRequest: null  
    function triggerTagSearch(query) {  
        if (currentTagRequest) {  
            currentTagRequest.abort();  
        }  
  
        var provider = providers[currentProvider]  
        if (!provider.tagSearchTemplate) {  
            return  
        }  
          
        var url = provider.tagSearchTemplate  
        if (currentProvider === "unsplash") {  
            url += "?query=" + encodeURIComponent(query) + "&per_page=10"  
        } else if (currentProvider === "wallhaven") {  
            url += "?q=" + encodeURIComponent(query)  
        }  
  
        var xhr = new XMLHttpRequest()  
        currentTagRequest = xhr  
        xhr.open("GET", url)  
        xhr.onreadystatechange = function() {  
            if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {  
                currentTagRequest = null  
                try {  
                    var response = JSON.parse(xhr.responseText)  
                    response = provider.tagMapFunc(response)  
                    root.tagSuggestion(query, response)  
                } catch (e) {  
                    console.log("[Wallpapers] Failed to parse tag suggestions: " + e)  
                }  
            }  
            else if (xhr.readyState === XMLHttpRequest.DONE) {  
                console.log("[Wallpapers] Tag search failed with status: " + xhr.status)  
            }  
        }  
  
        try {  
            if (currentProvider === "unsplash") {  
                xhr.setRequestHeader("Authorization", "Client-ID " + root.unsplashApiToken)  
            } else if (currentProvider === "pexels" && root.pexelsApiToken) {
                xhr.setRequestHeader("Authorization", root.pexelsApiToken)
            } else if (currentProvider === "wallhaven" && root.wallhavenApiToken) {  
                xhr.setRequestHeader("X-API-Key", root.wallhavenApiToken)  
            }  
            xhr.send()  
        } catch (error) {  
            console.log("Could not set headers:", error)  
        }     
    }  
}
