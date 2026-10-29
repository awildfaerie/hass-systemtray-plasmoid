import QtQuick 2.15
import QtQuick.Controls 2.15 as Controls
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import QtWebSockets 1.1
import QtWebEngine 1.10
import org.kde.kirigami 2.20 as Kirigami
import org.kde.plasma.plasmoid 2.0

PlasmoidItem {
    id: root

    implicitWidth: 420
    implicitHeight: 500
    activationTogglesExpanded: true
    readonly property int minimumDeviceTileWidth: 240
    readonly property bool homeAssistantConnected: homeAssistantSocket.status === WebSocket.Open

    property int nextCommandId: 1
    property int getStatesCommandId: 0
    property int subscribeCommandId: 0
    property int entityRegistryCommandId: 0
    property int deviceRegistryCommandId: 0
    property int areaRegistryCommandId: 0
    property int discoveryResponsesRemaining: 0
    property string connectionMessage: ""
    property bool connectionError: false
    property string discoveryError: ""
    property string discoveryWarning: ""
    property string connectionKey: Plasmoid.configuration.serverUrl + "\n"
                                  + Plasmoid.configuration.accessToken + "\n"
                                  + Plasmoid.configuration.entityIds
    property string deviceOrderKey: Plasmoid.configuration.deviceOrder || ""
    property string activeCameraEntityId: ""
    property string cameraStreamError: ""
    property bool cameraStreamLoading: false
    property var discoveredStates: []
    property var entityRegistryById: ({})
    property var devicesById: ({})
    property var areaNamesById: ({})
    property var tileModel: []

    Plasmoid.title: i18n("Home Assistant")
    Plasmoid.icon: "user-home-symbolic"

    compactRepresentation: Item {
        Layout.minimumWidth: 24
        Layout.minimumHeight: 24
        implicitWidth: 24
        implicitHeight: 24
        Accessible.name: Plasmoid.title
        Accessible.role: Accessible.Button

        Kirigami.Icon {
            anchors.fill: parent
            source: Plasmoid.icon
        }
    }

    function selectedEntityIds() {
        var configured = (Plasmoid.configuration.entityIds || "").split(/\r?\n/)
        var ids = []
        for (var i = 0; i < configured.length; ++i) {
            var entityId = configured[i].trim()
            if (entityId !== "" && ids.indexOf(entityId) === -1) {
                ids.push(entityId)
            }
        }
        return ids
    }

    function setConnectionStatus(message, isError) {
        connectionMessage = message
        connectionError = isError
    }

    function stopCameraStream() {
        activeCameraEntityId = ""
        cameraStreamLoading = false
        cameraStreamError = ""
        cameraWebView.url = "about:blank"
        cameraWindow.visible = false
    }

    function toggleCameraStream(entity) {
        console.info("[HomeAssistant Camera] stream button clicked for:",
                     entity.entityId)
        if (activeCameraEntityId === entity.entityId) {
            stopCameraStream()
            return
        }

        stopCameraStream()
        activeCameraEntityId = entity.entityId
        cameraStreamLoading = true
        cameraStreamError = ""
        cameraWindow.title = entity.name
        cameraWindow.visible = true
        cameraWebView.loadHtml(cameraStreamPageHtml(entity),
                               Plasmoid.configuration.serverUrl)
    }

    function cameraStreamPageHtml(entity) {
        var pageConfig = JSON.stringify({
            serverUrl: Plasmoid.configuration.serverUrl.trim().replace(/\/+$/, ""),
            entityId: entity.entityId,
            cameraToken: entity.cameraToken
        }).replace(/</g, "\\u003c")

        return [
            "<!doctype html>",
            "<html><head><meta charset=\"utf-8\">",
            "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
            "<style>",
            "html,body{margin:0;width:100%;height:100%;background:#000;color:#fff;",
            "font:14px sans-serif;overflow:hidden}",
            "body{display:flex;align-items:center;justify-content:center}",
            "img{width:100%;height:100%;object-fit:contain;background:#000}",
            "#status{position:absolute;left:16px;right:16px;bottom:16px;text-align:center;",
            "text-shadow:0 1px 3px #000;white-space:pre-wrap}",
            "</style></head><body>",
            "<img id=\"camera\" alt=\"Live camera stream\">",
            "<div id=\"status\">Connecting to camera…</div>",
            "<script>",
            "const settings=" + pageConfig + ";",
            "let startupTimer=setTimeout(()=>report(\"Timed out waiting for the camera stream.\"),30000);",
            "const camera=document.getElementById(\"camera\");",
            "const status=document.getElementById(\"status\");",
            "function report(text){status.textContent=text;",
            "if(text.indexOf(\"Live camera stream connected\")===0)clearTimeout(startupTimer);",
            "if(text.indexOf(\"Could not\")===0||text.indexOf(\"Timed out\")===0)",
            "clearTimeout(startupTimer);",
            "console.log(\"HA_CAMERA_STATUS:\"+text);}",
            "if(!settings.cameraToken){report(\"Camera access token is missing from Home Assistant state.\");}",
            "else{const streamUrl=new URL(settings.serverUrl.replace(/\\/+$/,\"\")",
            "+\"/api/camera_proxy_stream/\"+encodeURIComponent(settings.entityId));",
            "streamUrl.searchParams.set(\"token\",settings.cameraToken);",
            "camera.onload=()=>report(\"Live camera stream connected.\");",
            "camera.onerror=()=>report(\"Could not load the camera proxy stream.\");",
            "camera.src=streamUrl.toString();}",
            "</script></body></html>"
        ].join("\n")
    }

    function connectToHomeAssistant() {
        var baseUrl = Plasmoid.configuration.serverUrl.trim().replace(/\/+$/, "")
        var token = Plasmoid.configuration.accessToken.trim()
        if (baseUrl === "" || token === "") {
            setConnectionStatus(i18n("Configure the server URL and access token."), true)
            return
        }

        var ids = selectedEntityIds()
        if (ids.length === 0) {
            setConnectionStatus(i18n("Select entities in the widget settings."), false)
            return
        }

        entityModel.clear()
        tileModel = []
        entityRegistryById = ({})
        devicesById = ({})
        areaNamesById = ({})
        discoveredStates = null
        discoveryError = ""
        discoveryWarning = ""
        setConnectionStatus(i18n("Connecting to Home Assistant…"), false)
        var socketUrl = baseUrl.replace(/^https:/i, "wss:").replace(/^http:/i, "ws:")
        homeAssistantSocket.active = false
        homeAssistantSocket.url = socketUrl + "/api/websocket"
        homeAssistantSocket.active = true
    }

    function sendCommand(type, fields) {
        var id = nextCommandId++
        var command = fields || ({})
        command.id = id
        command.type = type
        homeAssistantSocket.sendTextMessage(JSON.stringify(command))
        return id
    }

    function boundedNumber(value, fallback, minimum, maximum) {
        var result = Number(value)
        if (!isFinite(result)) {
            return fallback
        }
        return Math.max(minimum, Math.min(maximum, result))
    }

    function handleStates(states) {
        entityModel.clear()
        var statesById = ({})
        for (var s = 0; s < states.length; ++s) {
            statesById[states[s].entity_id] = states[s]
        }

        var ids = selectedEntityIds()
        for (var i = 0; i < ids.length; ++i) {
            var state = statesById[ids[i]] || {
                entity_id: ids[i],
                state: "unavailable",
                attributes: {}
            }
            entityModel.append(entityItemForState(state))
        }

        rebuildTileModel()

        if (entityModel.count === 0) {
            setConnectionStatus(i18n("None of the selected entities were returned by Home Assistant."), true)
        } else {
            var message = i18n("Connected — showing %1 selected entities.", entityModel.count)
            if (discoveryWarning !== "") {
                message += " " + discoveryWarning
            }
            setConnectionStatus(message, discoveryWarning !== "")
        }
    }

    function finishDiscoveryResponse() {
        discoveryResponsesRemaining -= 1
        if (discoveryResponsesRemaining !== 0) {
            return
        }
        if (discoveryError !== "" || discoveredStates === null) {
            setConnectionStatus(discoveryError || i18n("Could not load entity states."), true)
            return
        }
        handleStates(discoveredStates)
    }

    function entityItemForState(state) {
        var attributes = state.attributes || ({})
        var domain = state.entity_id.split(".")[0]
        var registryEntry = entityRegistryById[state.entity_id] || ({})
        var device = devicesById[registryEntry.device_id] || ({})
        var areaId = registryEntry.area_id || device.area_id || ""
        var controlType = ""
        var canToggle = ["light", "switch", "input_boolean", "fan", "humidifier",
                         "siren", "water_heater", "cover", "media_player"].indexOf(domain) !== -1
        var minimum = 0
        var maximum = 100
        var value = 0
        var unit = attributes.unit_of_measurement || ""
        var actionLabel = i18n("Activate")

        if (domain === "input_number") {
            controlType = "number"
            minimum = Number(attributes.min !== undefined ? attributes.min : 0)
            maximum = Number(attributes.max !== undefined ? attributes.max : 100)
            if (!isFinite(minimum)) {
                minimum = 0
            }
            if (!isFinite(maximum) || maximum < minimum) {
                maximum = minimum + 100
            }
            value = boundedNumber(state.state, minimum, minimum, maximum)
        } else if (domain === "light" && attributes.brightness !== undefined) {
            controlType = "slider"
            minimum = 1
            maximum = 255
            value = boundedNumber(attributes.brightness, minimum, minimum, maximum)
            unit = i18n("brightness")
        } else if (domain === "fan" && attributes.percentage !== undefined) {
            controlType = "slider"
            value = boundedNumber(attributes.percentage, 0, minimum, maximum)
            unit = "%"
        } else if (domain === "media_player" && attributes.volume_level !== undefined) {
            controlType = "slider"
            maximum = 1
            value = boundedNumber(attributes.volume_level, 0, minimum, maximum)
            unit = i18n("volume")
        } else if (domain === "cover" && attributes.current_position !== undefined) {
            controlType = "slider"
            value = boundedNumber(attributes.current_position, 0, minimum, maximum)
            unit = "%"
        } else if (domain === "climate" && attributes.temperature !== undefined) {
            controlType = "dial"
            minimum = Number(attributes.min_temp !== undefined ? attributes.min_temp : 7)
            maximum = Number(attributes.max_temp !== undefined ? attributes.max_temp : 35)
            if (!isFinite(minimum)) {
                minimum = 7
            }
            if (!isFinite(maximum) || maximum < minimum) {
                maximum = minimum + 28
            }
            value = boundedNumber(attributes.temperature, minimum, minimum, maximum)
            unit = attributes.temperature_unit || ""
        } else if (domain === "button" || domain === "input_button") {
            controlType = "button"
            actionLabel = i18n("Press")
        } else if (domain === "script") {
            controlType = "button"
            actionLabel = i18n("Run")
        } else if (domain === "scene") {
            controlType = "button"
            actionLabel = i18n("Activate")
        } else if (domain === "camera") {
            controlType = "camera"
        }

        return {
            entityId: state.entity_id,
            name: attributes.friendly_name || state.entity_id,
            areaId: areaId,
            areaName: areaId ? areaNamesById[areaId] || i18n("Unknown area")
                            : i18n("No area"),
            deviceId: registryEntry.device_id || "",
            deviceName: device.name_by_user || device.name || i18n("Other entities"),
            domain: domain,
            state: state.state,
            available: state.state !== "unavailable" && state.state !== "unknown",
            cameraToken: attributes.access_token || "",
            controlType: controlType,
            canToggle: canToggle,
            minimum: minimum,
            maximum: maximum,
            value: value,
            unit: unit,
            actionLabel: actionLabel
        }
    }

    function rebuildTileModel() {
        var tilesByKey = ({})
        var tiles = []
        for (var i = 0; i < entityModel.count; ++i) {
            var entity = entityModel.get(i)
            var tileKey = entity.deviceId !== ""
                    ? "device:" + entity.deviceId : "other_entities"
            var tile = tilesByKey[tileKey]
            if (!tile) {
                tile = {
                    key: tileKey,
                    deviceId: entity.deviceId,
                    deviceName: entity.deviceName,
                    title: entity.deviceId !== "" ? entity.deviceName : i18n("Other entities"),
                    entities: []
                }
                tilesByKey[tileKey] = tile
                tiles.push(tile)
            }
            tile.entities.push(entity)
        }

        for (var tileIndex = 0; tileIndex < tiles.length; ++tileIndex) {
            if (tiles[tileIndex].entities.length === 1) {
                tiles[tileIndex].title = tiles[tileIndex].entities[0].name
            }
        }

        var orderedDeviceIds = deviceOrderKey.split(/\r?\n/)
        tiles.sort(function(left, right) {
            if (left.deviceId === "" || right.deviceId === "") {
                if (left.deviceId === right.deviceId) {
                    return left.deviceName.localeCompare(right.deviceName)
                }
                return left.deviceId === "" ? 1 : -1
            }
            var leftOrder = orderedDeviceIds.indexOf(left.deviceId)
            var rightOrder = orderedDeviceIds.indexOf(right.deviceId)
            if (leftOrder !== -1 && rightOrder !== -1) {
                return leftOrder - rightOrder
            }
            if (leftOrder !== -1) {
                return -1
            }
            if (rightOrder !== -1) {
                return 1
            }
            return left.title.localeCompare(right.title)
        })
        tileModel = tiles
    }

    onDeviceOrderKeyChanged: rebuildTileModel()

    function updateEntityState(state) {
        if (!state || selectedEntityIds().indexOf(state.entity_id) === -1) {
            return
        }

        var index = -1
        for (var i = 0; i < entityModel.count; ++i) {
            if (entityModel.get(i).entityId === state.entity_id) {
                index = i
                break
            }
        }

        if (index === -1) {
            entityModel.append(entityItemForState(state))
            rebuildTileModel()
            return
        }

        var updatedEntity = entityItemForState(state)
        for (var propertyName in updatedEntity) {
            entityModel.setProperty(index, propertyName, updatedEntity[propertyName])
        }
        rebuildTileModel()
    }

    function requestControl(entity, value) {
        var domain = entity.domain
        var service = ""
        var serviceData = { entity_id: entity.entityId }

        if (value === "press") {
            if (domain === "button" || domain === "input_button") {
                service = "press"
            } else if (domain === "script") {
                service = "turn_on"
            } else if (domain === "scene") {
                service = "turn_on"
            }
        } else if (typeof value === "boolean") {
            if (domain === "cover") {
                service = value ? "open_cover" : "close_cover"
            } else if (domain === "media_player") {
                service = value ? "media_play" : "media_pause"
            } else {
                service = value ? "turn_on" : "turn_off"
            }
        } else {
            var numericValue = Number(value)
            if (!isFinite(numericValue)) {
                setConnectionStatus(i18n("Invalid value for %1.", entity.name), true)
                return
            }

            if (domain === "input_number") {
                service = "set_value"
                serviceData.value = numericValue
            } else if (domain === "light") {
                service = "turn_on"
                serviceData.brightness = Math.round(numericValue)
            } else if (domain === "fan") {
                service = "set_percentage"
                serviceData.percentage = Math.round(numericValue)
            } else if (domain === "media_player") {
                service = "volume_set"
                serviceData.volume_level = numericValue
            } else if (domain === "cover") {
                service = "set_cover_position"
                serviceData.position = Math.round(numericValue)
            } else if (domain === "climate") {
                service = "set_temperature"
                serviceData.temperature = numericValue
            }
        }

        if (service === "") {
            setConnectionStatus(i18n("No supported control is available for %1.", entity.entityId), true)
            return
        }

        var requestId = sendCommand("call_service", {
            domain: domain,
            service: service,
            service_data: serviceData
        })
        pendingServiceRequests[requestId] = entity.name
    }

    function handleServiceResult(message) {
        var entityName = pendingServiceRequests[message.id] || i18n("Entity")
        delete pendingServiceRequests[message.id]
        if (!message.success) {
            var reason = message.error && message.error.message
                    ? message.error.message : i18n("Home Assistant rejected the service call.")
            setConnectionStatus(i18n("Could not control %1: %2", entityName, reason), true)
        }
    }

    onExpandedChanged: function(isExpanded) {
        if (isExpanded && !homeAssistantSocket.active) {
            connectToHomeAssistant()
        }
    }

    onConnectionKeyChanged: {
        stopCameraStream()
        if (homeAssistantSocket.active) {
            homeAssistantSocket.active = false
        }
        entityModel.clear()
        if (expanded) {
            Qt.callLater(connectToHomeAssistant)
        }
    }

    Component.onCompleted: {
        if (expanded) {
            connectToHomeAssistant()
        }
    }

    WebSocket {
        id: homeAssistantSocket
        active: false

        onStatusChanged: function(status) {
            console.info("[HomeAssistant] WebSocket status:",
                         status)
            if (status === WebSocket.Error) {
                root.setConnectionStatus(errorString || i18n("Unable to connect to Home Assistant."), true)
                active = false
            }
        }

        onTextMessageReceived: function(message) {
            var response
            try {
                response = JSON.parse(message)
            } catch (error) {
                root.setConnectionStatus(i18n("Home Assistant sent an invalid response."), true)
                homeAssistantSocket.active = false
                return
            }

            if (response.type === "auth_required") {
                homeAssistantSocket.sendTextMessage(JSON.stringify({
                    type: "auth",
                    access_token: Plasmoid.configuration.accessToken.trim()
                }))
            } else if (response.type === "auth_ok") {
                root.discoveryWarning = ""
                root.discoveryError = ""
                root.discoveredStates = null
                root.entityRegistryById = ({})
                root.devicesById = ({})
                root.areaNamesById = ({})
                root.discoveryResponsesRemaining = 4
                root.getStatesCommandId = root.sendCommand("get_states")
                root.subscribeCommandId = root.sendCommand("subscribe_events", {
                    event_type: "state_changed"
                })
                root.entityRegistryCommandId = root.sendCommand("config/entity_registry/list")
                root.deviceRegistryCommandId = root.sendCommand("config/device_registry/list")
                root.areaRegistryCommandId = root.sendCommand("config/area_registry/list")
            } else if (response.type === "auth_invalid") {
                root.setConnectionStatus(i18n("Authentication failed. Check the access token."), true)
                homeAssistantSocket.active = false
            } else if (response.type === "result") {
                if (response.id === root.getStatesCommandId) {
                    if (response.success) {
                        root.discoveredStates = response.result
                    } else {
                        var stateError = response.error && response.error.message
                                ? response.error.message : i18n("unknown error")
                        root.discoveryError = i18n("Could not load entity states: %1",
                                                   stateError)
                        root.discoveredStates = null
                    }
                    root.finishDiscoveryResponse()
                } else if (response.id === root.entityRegistryCommandId
                           || response.id === root.deviceRegistryCommandId
                           || response.id === root.areaRegistryCommandId) {
                    if (response.success) {
                        if (response.id === root.entityRegistryCommandId) {
                            var entitiesById = ({})
                            for (var e = 0; e < response.result.length; ++e) {
                                entitiesById[response.result[e].entity_id] = response.result[e]
                            }
                            root.entityRegistryById = entitiesById
                        } else if (response.id === root.deviceRegistryCommandId) {
                            var devicesById = ({})
                            for (var d = 0; d < response.result.length; ++d) {
                                devicesById[response.result[d].id] = response.result[d]
                            }
                            root.devicesById = devicesById
                        } else {
                            var areaNamesById = ({})
                            for (var a = 0; a < response.result.length; ++a) {
                                areaNamesById[response.result[a].area_id] = response.result[a].name
                            }
                            root.areaNamesById = areaNamesById
                        }
                    } else {
                        var registryError = response.error && response.error.message
                                ? response.error.message : i18n("unknown error")
                        var warning = i18n("Some area or device details are unavailable: %1",
                                           registryError)
                        root.discoveryWarning = root.discoveryWarning === ""
                                ? warning : root.discoveryWarning + " " + warning
                    }
                    root.finishDiscoveryResponse()
                } else if (response.id === root.subscribeCommandId && !response.success) {
                    var subscriptionError = response.error && response.error.message
                            ? response.error.message : i18n("unknown error")
                    root.setConnectionStatus(i18n("Could not subscribe to live state updates: %1",
                                                   subscriptionError), true)
                } else if (root.pendingServiceRequests[response.id] !== undefined) {
                    root.handleServiceResult(response)
                }
            } else if (response.type === "event"
                       && response.event && response.event.event_type === "state_changed") {
                root.updateEntityState(response.event.data.new_state)
            }
        }
    }

    property var pendingServiceRequests: ({})

    ListModel {
        id: entityModel
    }

    Window {
        id: cameraWindow
        width: 720
        height: 480
        visible: false
        color: "black"
        title: i18n("Camera stream")

        onVisibleChanged: {
            if (!visible && root.activeCameraEntityId !== "") {
                root.stopCameraStream()
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Controls.Label {
                    Layout.fillWidth: true
                    text: cameraWindow.title
                    elide: Text.ElideRight
                }
                Controls.Button {
                    text: i18n("Close")
                    onClicked: root.stopCameraStream()
                }
            }

            WebEngineView {
                id: cameraWebView
                Layout.fillWidth: true
                Layout.fillHeight: true
                backgroundColor: "black"
                onJavaScriptConsoleMessage: function(level, message, lineNumber, sourceID) {
                    var prefix = "HA_CAMERA_STATUS:"
                    if (message.indexOf(prefix) === 0) {
                        var status = message.substring(prefix.length)
                        var connected = status.indexOf("Live camera stream connected") === 0
                        var failed = status.indexOf("failed") !== -1
                                || status.indexOf("Could not") === 0
                                || status.indexOf("Camera access token is missing") === 0
                                || status.indexOf("rejected") !== -1
                                || status.indexOf("Timed out") === 0
                                || status.indexOf("interrupted") !== -1
                                || status.indexOf("closed") !== -1
                        root.cameraStreamLoading = !connected && !failed
                        root.cameraStreamError = failed ? status : ""
                        console.info("[HomeAssistant Camera]", status)
                    }
                }
                onLoadingChanged: function(loadingInfo) {
                    if (loadingInfo.status === WebEngineView.LoadFailedStatus) {
                        root.cameraStreamLoading = false
                        root.cameraStreamError = i18n("Could not load the camera stream viewer.")
                    }
                }
            }
        }
    }

    fullRepresentation: ColumnLayout {
        id: fullRepresentationRoot
        Layout.minimumWidth: 420
        Layout.preferredWidth: 420
        implicitWidth: 420
        spacing: 10

        Component.onCompleted: {
            console.info("[HomeAssistant Layout] full representation initialized; width:",
                         width, "implicit width:", implicitWidth,
                         "minimum width:", Layout.minimumWidth,
                         "preferred width:", Layout.preferredWidth)
        }
        onWidthChanged: {
            console.info("[HomeAssistant Layout] full representation width:", width,
                         "implicit width:", implicitWidth,
                         "minimum width:", Layout.minimumWidth,
                         "preferred width:", Layout.preferredWidth)
        }

        Controls.Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            visible: root.connectionError && root.connectionMessage !== ""
            color: root.connectionError ? "red" : palette.windowText
            text: root.connectionMessage
        }

        Controls.ScrollView {
            id: areaScrollView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            background: null
            contentWidth: availableWidth

            Component.onCompleted: {
                console.info("[HomeAssistant Layout] scroll view initialized; width:",
                             width, "implicit width:", implicitWidth,
                             "minimum width:", Layout.minimumWidth,
                             "preferred width:", Layout.preferredWidth)
            }
            onWidthChanged: {
                console.info("[HomeAssistant Layout] scroll view width:", width,
                             "implicit width:", implicitWidth,
                             "minimum width:", Layout.minimumWidth,
                             "preferred width:", Layout.preferredWidth)
            }

            ColumnLayout {
                id: areaScrollContents
                width: areaScrollView.availableWidth

                Component.onCompleted: {
                    console.info("[HomeAssistant Layout] scroll contents initialized; width:",
                                 width, "parent width:", parent.width,
                                 "implicit width:", implicitWidth)
                }
                onWidthChanged: {
                    console.info("[HomeAssistant Layout] scroll contents width:", width,
                                 "parent width:", parent.width,
                                 "implicit width:", implicitWidth)
                }

                Controls.Label {
                    Layout.fillWidth: true
                    visible: entityModel.count === 0
                    wrapMode: Text.WordWrap
                    text: root.selectedEntityIds().length === 0
                          ? i18n("Select entities in the widget settings.")
                          : i18n("Waiting for selected entity states.")
                }

                Item {
                    id: masonryGrid
                    Layout.fillWidth: true
                    Layout.rightMargin: 16
                    implicitHeight: contentHeight
                    property int spacing: 16
                    property int columns: Math.max(
                        1,
                        Math.floor((width + spacing)
                                   / (root.minimumDeviceTileWidth + spacing)))
                    property real columnWidth: Math.max(
                        0,
                        (width - (columns - 1) * spacing) / columns)
                    property real contentHeight: 0
                    property bool arranging: false

                    function arrangeTiles() {
                        if (arranging) {
                            return
                        }
                        arranging = true
                        var heights = []
                        for (var column = 0; column < columns; ++column) {
                            heights.push(0)
                        }

                        for (var i = 0; i < tileRepeater.count; ++i) {
                            var tile = tileRepeater.itemAt(i)
                            if (!tile) {
                                continue
                            }
                            var shortestColumn = 0
                            for (var c = 1; c < columns; ++c) {
                                if (heights[c] < heights[shortestColumn]) {
                                    shortestColumn = c
                                }
                            }
                            tile.masonryColumn = shortestColumn
                            tile.masonryY = heights[shortestColumn]
                            heights[shortestColumn] += Math.max(
                                tile.height, tile.implicitHeight) + spacing
                        }

                        var maxHeight = 0
                        for (var h = 0; h < heights.length; ++h) {
                            maxHeight = Math.max(maxHeight, heights[h])
                        }
                        contentHeight = Math.max(0, maxHeight - spacing)
                        arranging = false
                    }

                    onWidthChanged: Qt.callLater(arrangeTiles)
                    onColumnsChanged: Qt.callLater(arrangeTiles)

                    Repeater {
                        id: tileRepeater
                        model: root.tileModel
                        onItemAdded: Qt.callLater(masonryGrid.arrangeTiles)
                        onItemRemoved: Qt.callLater(masonryGrid.arrangeTiles)

                        delegate: Controls.Frame {
                            id: deviceTile
                            required property var modelData
                            property int masonryColumn: 0
                            property real masonryY: 0
                            x: masonryColumn * (masonryGrid.columnWidth + masonryGrid.spacing)
                            y: masonryY
                            width: masonryGrid.columnWidth
                            height: implicitHeight
                            onHeightChanged: Qt.callLater(masonryGrid.arrangeTiles)

                            ColumnLayout {
                                anchors.fill: parent

                                Controls.Label {
                                    Layout.fillWidth: true
                                    Layout.minimumWidth: 0
                                    text: deviceTile.modelData.title
                                    font.bold: true
                                    font.pixelSize: 16
                                    wrapMode: Text.WordWrap
                                }

                                Repeater {
                                    model: deviceTile.modelData.entities
                                    delegate: EntityControl {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        entity: modelData
                                        cameraStreamActive: root.activeCameraEntityId === modelData.entityId
                                        cameraStreamLoading: cameraStreamActive
                                                                    && root.cameraStreamLoading
                                        cameraStreamEnabled: root.homeAssistantConnected
                                        showName: modelData.name !== deviceTile.modelData.title
                                        onValueRequested: function(value) {
                                            root.requestControl(entity, value)
                                        }
                                        onCameraStreamRequested: {
                                            root.toggleCameraStream(entity)
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

    Component.onDestruction: stopCameraStream()

    Plasmoid.configurationRequired: false
}
