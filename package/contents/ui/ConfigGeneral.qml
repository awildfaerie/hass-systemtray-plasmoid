import QtQuick 2.15
import QtQuick.Controls 2.15 as Controls
import QtQuick.Dialogs
import QtQuick.Layouts 1.15
import QtWebSockets 1.1
import "HomeAssistant/BackupReader" as BackupReader

Item {
    id: root

    property alias cfg_serverUrl: serverUrl.text
    property alias cfg_accessToken: accessToken.text
    property alias cfg_entityIds: root.entityIds
    property alias cfg_deviceOrder: root.deviceOrder

    property string entityIds: ""
    property string deviceOrder: ""
    property var devices: []
    property var entities: []
    property var areas: []
    property var statesByEntity: ({})
    property int pendingResponses: 0
    property bool discoveryInProgress: false
    property string selectedDeviceId: deviceFilter.currentIndex < 0
            ? "" : deviceFilter.currentValue
    property string selectedAreaId: areaFilter.currentValue || ""
    property string registryWarning: ""

    implicitWidth: 520
    implicitHeight: 620

    function setStatus(message, isError) {
        statusLabel.text = message
        statusLabel.isError = isError
    }

    function createBackup() {
        var backup = {
            version: 1,
            serverUrl: serverUrl.text,
            accessToken: accessToken.text,
            entityIds: entityIds,
            deviceOrder: deviceOrder
        }
        backupText.text = JSON.stringify(backup, null, 2)
        backupText.selectAll()
        backupText.copy()
        backupText.deselect()
        setStatus(i18n("Backup copied. Save it in a secure location."), false)
    }

    function restoreBackup(contents) {
        var backup
        try {
            backup = JSON.parse(contents)
        } catch (error) {
            setStatus(i18n("The backup is not valid JSON."), true)
            return
        }

        if (!backup || backup.version !== 1
                || typeof backup.serverUrl !== "string"
                || typeof backup.accessToken !== "string"
                || typeof backup.entityIds !== "string"
                || (backup.deviceOrder !== undefined
                    && typeof backup.deviceOrder !== "string")) {
            setStatus(i18n("The backup format is invalid or unsupported."), true)
            return
        }

        serverUrl.text = backup.serverUrl
        accessToken.text = backup.accessToken
        entityIds = backup.entityIds
        deviceOrder = backup.deviceOrder || ""
        setStatus(i18n("Configuration restored. Apply the settings to save them."), false)
    }

    function loadBackupFile(url) {
        var result = backupFileReader.readFile(url)
        if (result.error) {
            setStatus(i18n("Could not read the selected backup file: %1",
                           result.error), true)
            return
        }
        restoreBackup(result.contents)
    }

    function connectToHomeAssistant() {
        var baseUrl = serverUrl.text.trim().replace(/\/+$/, "")
        if (!/^https?:\/\//i.test(baseUrl)) {
            setStatus(i18n("Enter a server URL beginning with http:// or https://."), true)
            return
        }
        if (accessToken.text.trim() === "") {
            setStatus(i18n("Enter a long-lived access token."), true)
            return
        }

        devices = []
        entities = []
        areas = []
        statesByEntity = ({})
        registryWarning = ""
        pendingResponses = 4
        discoveryInProgress = true
        areaModel.clear()
        deviceModel.clear()
        entityModel.clear()
        areaModel.append({ areaId: "", name: i18n("All areas") })
        areaModel.append({ areaId: "__no_area__", name: i18n("No area") })
        deviceFilter.currentIndex = -1
        setStatus(i18n("Connecting to Home Assistant…"), false)

        var socketUrl = baseUrl.replace(/^https:/i, "wss:").replace(/^http:/i, "ws:")
        homeAssistantSocket.active = false
        homeAssistantSocket.url = socketUrl + "/api/websocket"
        homeAssistantSocket.active = true
    }

    function sendCommand(id, type) {
        homeAssistantSocket.sendTextMessage(JSON.stringify({ id: id, type: type }))
    }

    function handleResult(message) {
        if (!message.success) {
            var errorMessage = message.error && message.error.message
                    ? message.error.message : i18n("Home Assistant rejected a discovery request.")
            if (message.id === 3) {
                discoveryInProgress = false
                pendingResponses = 0
                setStatus(errorMessage, true)
                homeAssistantSocket.active = false
                return
            }

            registryWarning = errorMessage
            if (message.id === 1) {
                devices = []
            } else if (message.id === 2) {
                entities = []
            } else if (message.id === 4) {
                areas = []
            }
            finishDiscoveryResponse()
            return
        }

        if (message.id === 1) {
            devices = message.result
        } else if (message.id === 2) {
            entities = message.result
        } else if (message.id === 3) {
            var stateMap = ({})
            for (var i = 0; i < message.result.length; ++i) {
                stateMap[message.result[i].entity_id] = message.result[i]
            }
            statesByEntity = stateMap
        } else if (message.id === 4) {
            areas = message.result
        }

        finishDiscoveryResponse()
    }

    function finishDiscoveryResponse() {
        pendingResponses -= 1
        if (pendingResponses === 0) {
            populateEntityModel()
            homeAssistantSocket.active = false
            discoveryInProgress = false
            var summary = i18n("Found %1 entities across %2 devices.",
                               entityModel.count, devices.length)
            if (registryWarning !== "") {
                summary += " " + i18n("Some device or area details were unavailable: %1",
                                      registryWarning)
            }
            setStatus(summary, registryWarning !== "")
        }
    }

    function populateEntityModel() {
        areaModel.clear()
        areaModel.append({ areaId: "", name: i18n("All areas") })
        areaModel.append({ areaId: "__no_area__", name: i18n("No area") })
        var areaNames = ({})
        var areaIds = ({})
        for (var a = 0; a < areas.length; ++a) {
            areaNames[areas[a].area_id] = areas[a].name || areas[a].area_id
            areaIds[areas[a].area_id] = true
        }
        for (var da = 0; da < devices.length; ++da) {
            if (devices[da].area_id) {
                areaIds[devices[da].area_id] = true
            }
        }
        for (var ea = 0; ea < entities.length; ++ea) {
            if (entities[ea].area_id) {
                areaIds[entities[ea].area_id] = true
            }
        }
        var sortedAreaIds = Object.keys(areaIds).sort(function(left, right) {
            var leftName = areaNames[left] || left
            var rightName = areaNames[right] || right
            return leftName.localeCompare(rightName)
        })
        for (var ai = 0; ai < sortedAreaIds.length; ++ai) {
            var areaId = sortedAreaIds[ai]
            areaModel.append({
                areaId: areaId,
                name: areaNames[areaId] || i18n("Unknown area (%1)", areaId)
            })
        }

        var deviceNames = ({})
        var deviceAreas = ({})
        for (var d = 0; d < devices.length; ++d) {
            var device = devices[d]
            deviceNames[device.id] = device.name_by_user || device.name || device.id
            deviceAreas[device.id] = device.area_id || ""
        }
        var stateMap = statesByEntity
        var registryByEntity = ({})
        for (var r = 0; r < entities.length; ++r) {
            registryByEntity[entities[r].entity_id] = entities[r]
        }

        entityModel.clear()
        var stateIds = Object.keys(stateMap).sort()
        for (var s = 0; s < stateIds.length; ++s) {
            var entityId = stateIds[s]
            var registryEntry = registryByEntity[entityId] || ({})
            if (registryEntry.disabled_by) {
                continue
            }
            var deviceId = registryEntry.device_id || ""
            var deviceName = deviceId && deviceNames[deviceId]
                    ? deviceNames[deviceId] : i18n("Other entities")
            var entityAreaId = registryEntry.area_id
                    || (deviceId ? deviceAreas[deviceId] : "") || ""
            var state = stateMap[entityId]
            var attributes = state.attributes || ({})
            entityModel.append({
                entityId: entityId,
                name: attributes.friendly_name || registryEntry.name
                      || registryEntry.original_name || entityId,
                deviceId: deviceId,
                deviceName: deviceName,
                areaId: entityAreaId,
                areaName: entityAreaId && areaNames[entityAreaId]
                        ? areaNames[entityAreaId]
                        : entityAreaId ? i18n("Unknown area (%1)", entityAreaId)
                                       : i18n("No area"),
                state: state.state
            })
        }

        areaFilter.currentIndex = 0
        rebuildDeviceModel(deviceNames)
    }

    function rebuildDeviceModel(deviceNames) {
        deviceModel.clear()
        deviceModel.append({ deviceId: "", name: i18n("All devices") })
        var knownDeviceNames = deviceNames || ({})
        var visibleDevices = ({})
        var hasOtherEntities = false

        for (var i = 0; i < entityModel.count; ++i) {
            var entity = entityModel.get(i)
            var matchesArea = selectedAreaId === ""
                    || (selectedAreaId === "__no_area__" && entity.areaId === "")
                    || entity.areaId === selectedAreaId
            if (!matchesArea) {
                continue
            }
            if (entity.deviceId === "") {
                hasOtherEntities = true
            } else {
                visibleDevices[entity.deviceId] = knownDeviceNames[entity.deviceId]
                        || entity.deviceName
            }
        }

        if (hasOtherEntities) {
            deviceModel.append({ deviceId: "__no_device__", name: i18n("Other entities") })
        }

        var sortedDeviceIds = Object.keys(visibleDevices).sort(function(left, right) {
            return visibleDevices[left].localeCompare(visibleDevices[right])
        })
        for (var d = 0; d < sortedDeviceIds.length; ++d) {
            var deviceId = sortedDeviceIds[d]
            deviceModel.append({
                deviceId: deviceId,
                name: visibleDevices[deviceId]
            })
        }

        deviceFilter.currentIndex = 0
    }

    function isEntitySelected(entityId) {
        return entityIds.split(/\r?\n/).indexOf(entityId) !== -1
    }

    function setEntitySelected(entityId, selected) {
        var current = entityIds.split(/\r?\n/)
        var updated = []
        for (var i = 0; i < current.length; ++i) {
            var value = current[i].trim()
            if (value !== "" && value !== entityId && updated.indexOf(value) === -1) {
                updated.push(value)
            }
        }
        if (selected) {
            updated.push(entityId)
        }
        entityIds = updated.join("\n")
    }

    function entityGroupKey(entity) {
        return entity.deviceId !== "" ? "device:" + entity.deviceId
                                      : "other_entities"
    }

    function selectedEntityIdsForGroup(groupKey) {
        var groupKeysByEntityId = ({})
        for (var i = 0; i < entityModel.count; ++i) {
            var entity = entityModel.get(i)
            groupKeysByEntityId[entity.entityId] = entityGroupKey(entity)
        }
        var groupEntityIds = []
        var orderedIds = entityIds.split(/\r?\n/)
        for (var j = 0; j < orderedIds.length; ++j) {
            if (groupKeysByEntityId[orderedIds[j]] === groupKey) {
                groupEntityIds.push(orderedIds[j])
            }
        }
        return groupEntityIds
    }

    function moveSelectedEntity(entityId, offset) {
        var orderedIds = entityIds.split(/\r?\n/).filter(function(id) {
            return id.trim() !== ""
        })
        var entityIndex = -1
        for (var i = 0; i < entityModel.count; ++i) {
            if (entityModel.get(i).entityId === entityId) {
                entityIndex = i
                break
            }
        }
        if (entityIndex < 0) {
            return
        }

        var groupKey = entityGroupKey(entityModel.get(entityIndex))
        var groupEntityIds = selectedEntityIdsForGroup(groupKey)
        var groupIndex = groupEntityIds.indexOf(entityId)
        var targetGroupIndex = groupIndex + offset
        if (groupIndex < 0 || targetGroupIndex < 0 || targetGroupIndex >= groupEntityIds.length) {
            return
        }

        var targetEntityId = groupEntityIds[targetGroupIndex]
        var currentIndex = orderedIds.indexOf(entityId)
        var targetIndex = orderedIds.indexOf(targetEntityId)
        orderedIds[currentIndex] = targetEntityId
        orderedIds[targetIndex] = entityId
        entityIds = orderedIds.join("\n")
    }

    function canMoveSelectedEntity(entityId, offset) {
        var selectedIndex = entityIds.split(/\r?\n/).indexOf(entityId)
        if (selectedIndex < 0) {
            return false
        }
        var entityIndex = -1
        for (var i = 0; i < entityModel.count; ++i) {
            if (entityModel.get(i).entityId === entityId) {
                entityIndex = i
                break
            }
        }
        if (entityIndex < 0) {
            return false
        }
        var groupKey = entityGroupKey(entityModel.get(entityIndex))
        var groupEntityIds = selectedEntityIdsForGroup(groupKey)
        var groupIndex = groupEntityIds.indexOf(entityId)
        return groupIndex + offset >= 0 && groupIndex + offset < groupEntityIds.length
    }

    function selectedDevices() {
        var selectedIds = entityIds.split(/\r?\n/)
        var devicesById = ({})
        for (var i = 0; i < entityModel.count; ++i) {
            var entity = entityModel.get(i)
            if (entity.deviceId !== ""
                    && selectedIds.indexOf(entity.entityId) !== -1) {
                devicesById[entity.deviceId] = entity.deviceName
            }
        }

        var deviceIds = Object.keys(devicesById)
        var savedOrder = deviceOrder.split(/\r?\n/)
        deviceIds.sort(function(left, right) {
            var leftIndex = savedOrder.indexOf(left)
            var rightIndex = savedOrder.indexOf(right)
            if (leftIndex !== -1 && rightIndex !== -1) {
                return leftIndex - rightIndex
            }
            if (leftIndex !== -1) {
                return -1
            }
            if (rightIndex !== -1) {
                return 1
            }
            return devicesById[left].localeCompare(devicesById[right])
        })
        return deviceIds
    }

    function isFirstSelectedEntityForDevice(entityId) {
        var entityIndex = -1
        for (var i = 0; i < entityModel.count; ++i) {
            if (entityModel.get(i).entityId === entityId) {
                entityIndex = i
                break
            }
        }
        if (entityIndex < 0) {
            return false
        }
        var entity = entityModel.get(entityIndex)
        if (entity.deviceId === "") {
            return false
        }
        var groupEntityIds = selectedEntityIdsForGroup(entityGroupKey(entity))
        return groupEntityIds.length > 0 && groupEntityIds[0] === entityId
    }

    function canMoveDeviceTile(entityId, offset) {
        var entityIndex = -1
        for (var i = 0; i < entityModel.count; ++i) {
            if (entityModel.get(i).entityId === entityId) {
                entityIndex = i
                break
            }
        }
        if (entityIndex < 0) {
            return false
        }
        var entity = entityModel.get(entityIndex)
        if (entity.deviceId === "") {
            return false
        }
        var deviceIds = selectedDevices()
        var deviceIndex = deviceIds.indexOf(entity.deviceId)
        return deviceIndex + offset >= 0 && deviceIndex + offset < deviceIds.length
    }

    function moveDeviceTile(entityId, offset) {
        var entityIndex = -1
        for (var i = 0; i < entityModel.count; ++i) {
            if (entityModel.get(i).entityId === entityId) {
                entityIndex = i
                break
            }
        }
        if (entityIndex < 0) {
            return
        }
        var entity = entityModel.get(entityIndex)
        var deviceIds = selectedDevices()
        var deviceIndex = deviceIds.indexOf(entity.deviceId)
        var targetIndex = deviceIndex + offset
        if (deviceIndex < 0 || targetIndex < 0 || targetIndex >= deviceIds.length) {
            return
        }

        var movedDeviceId = deviceIds[targetIndex]
        deviceIds[targetIndex] = deviceIds[deviceIndex]
        deviceIds[deviceIndex] = movedDeviceId
        var orderedDeviceIds = deviceOrder.split(/\r?\n/).filter(function(id) {
            return id.trim() !== "" && deviceIds.indexOf(id) === -1
        })
        deviceOrder = orderedDeviceIds.concat(deviceIds).join("\n")
    }

    function matchesFilters(entity) {
        var matchesArea = selectedAreaId === ""
                || (selectedAreaId === "__no_area__" && entity.areaId === "")
                || entity.areaId === selectedAreaId
        var matchesDevice = selectedDeviceId === ""
                || (selectedDeviceId === "__no_device__" && entity.deviceId === "")
                || entity.deviceId === selectedDeviceId
        return matchesArea && matchesDevice
    }

    function selectVisibleEntities(selected) {
        var selectedIds = []
        var currentIds = entityIds.split(/\r?\n/)
        for (var c = 0; c < currentIds.length; ++c) {
            var currentId = currentIds[c].trim()
            if (currentId !== "" && selectedIds.indexOf(currentId) === -1) {
                selectedIds.push(currentId)
            }
        }

        for (var i = 0; i < entityModel.count; ++i) {
            var entity = entityModel.get(i)
            if (matchesFilters(entity)) {
                if (selected) {
                    if (selectedIds.indexOf(entity.entityId) === -1) {
                        selectedIds.push(entity.entityId)
                    }
                } else {
                    var selectedIndex = selectedIds.indexOf(entity.entityId)
                    if (selectedIndex !== -1) {
                        selectedIds.splice(selectedIndex, 1)
                    }
                }
            }
        }

        entityIds = selectedIds.join("\n")
    }

    function visibleEntityCount() {
        var count = 0
        for (var i = 0; i < entityModel.count; ++i) {
            if (matchesFilters(entityModel.get(i))) {
                count += 1
            }
        }
        return count
    }

    Component.onCompleted: {
        if (serverUrl.text.trim() !== "" && accessToken.text.trim() !== "") {
            connectToHomeAssistant()
        }
    }

    WebSocket {
        id: homeAssistantSocket
        active: false

        onStatusChanged: {
            if (status === WebSocket.Error) {
                root.discoveryInProgress = false
                root.pendingResponses = 0
                root.setStatus(errorString || i18n("Unable to connect to Home Assistant."), true)
                active = false
            }
        }

        onTextMessageReceived: function(message) {
            var response
            try {
                response = JSON.parse(message)
            } catch (error) {
                root.discoveryInProgress = false
                root.pendingResponses = 0
                root.setStatus(i18n("Home Assistant sent an invalid response."), true)
                homeAssistantSocket.active = false
                return
            }

            if (response.type === "auth_required") {
                homeAssistantSocket.sendTextMessage(JSON.stringify({
                    type: "auth",
                    access_token: accessToken.text.trim()
                }))
            } else if (response.type === "auth_ok") {
                root.setStatus(i18n("Retrieving devices, areas, and entities…"), false)
                root.sendCommand(1, "config/device_registry/list")
                root.sendCommand(2, "config/entity_registry/list")
                root.sendCommand(3, "get_states")
                root.sendCommand(4, "config/area_registry/list")
            } else if (response.type === "auth_invalid") {
                root.discoveryInProgress = false
                root.pendingResponses = 0
                root.setStatus(i18n("Authentication failed. Check the access token."), true)
                homeAssistantSocket.active = false
            } else if (response.type === "result") {
                root.handleResult(response)
            }
        }
    }

    ListModel {
        id: areaModel
    }

    ListModel {
        id: deviceModel
    }

    ListModel {
        id: entityModel
    }

    Controls.ScrollView {
        id: configScrollView
        anchors.fill: parent
        clip: true
        contentWidth: availableWidth

        ColumnLayout {
            width: configScrollView.availableWidth
            spacing: 10

            Controls.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18n("Connect to Home Assistant and choose the entities to show in the widget.")
            }

            Controls.Label {
                text: i18n("Server URL")
            }

            Controls.TextField {
                id: serverUrl
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                placeholderText: "http://homeassistant.local:8123"
                inputMethodHints: Qt.ImhUrlCharactersOnly
            }

            Controls.Label {
                text: i18n("Long-lived access token")
            }

            Controls.TextField {
                id: accessToken
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                echoMode: TextInput.Password
                placeholderText: i18n("Paste your Home Assistant access token")
            }

            Controls.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18n("The token is stored unencrypted in the widget's local configuration. Use a dedicated Home Assistant account with permission to read states and device/entity registries.")
            }

            Controls.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18n("Use HTTPS when connecting over an untrusted network; the access token is sent to the server during authentication.")
            }

            Controls.Label {
                text: i18n("Configuration backup")
                font.bold: true
            }

            Controls.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18n("Backups contain your access token in plain text. Store them securely and do not share them.")
            }

            RowLayout {
                Layout.fillWidth: true

                Controls.Button {
                    text: i18n("Copy backup")
                    onClicked: root.createBackup()
                }

                Controls.Button {
                    text: i18n("Load backup file…")
                    onClicked: backupFileDialog.open()
                }
            }

            Controls.TextArea {
                id: backupText
                readOnly: true
                visible: false
            }

            RowLayout {
                Layout.fillWidth: true

                Controls.BusyIndicator {
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    running: root.discoveryInProgress
                    visible: running
                    Accessible.name: i18n("Discovering Home Assistant devices and entities")
                }

                Controls.Button {
                    text: i18n("Discover devices and entities")
                    enabled: !root.discoveryInProgress
                    onClicked: root.connectToHomeAssistant()
                }

                Controls.Label {
                    id: statusLabel
                    property bool isError: false
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    color: isError ? "red" : palette.windowText
                }
            }

            Controls.Label {
                text: i18n("Filter by area")
            }

            Controls.ComboBox {
                id: areaFilter
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                textRole: "name"
                valueRole: "areaId"
                model: areaModel
                onActivated: root.rebuildDeviceModel()
            }

            Controls.Label {
                text: i18n("Filter by device")
            }

            Controls.ComboBox {
                id: deviceFilter
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                textRole: "name"
                valueRole: "deviceId"
                model: deviceModel
                currentIndex: -1
            }

            RowLayout {
                Controls.Button {
                    text: i18n("Select all")
                    enabled: entityModel.count > 0
                    onClicked: root.selectVisibleEntities(true)
                }

                Controls.Button {
                    text: i18n("Clear selection")
                    enabled: entityModel.count > 0
                    onClicked: root.selectVisibleEntities(false)
                }
            }

            Controls.Label {
                text: i18n("Available entities")
                font.bold: true
            }

            Controls.Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: i18n("Use the entity arrows to set order within a tile and the device arrows to set the global tile order.")
            }

            Controls.Label {
                text: i18n("%1 entities match the current filters.", root.visibleEntityCount())
                visible: entityModel.count > 0
            }

            Controls.Label {
                Layout.fillWidth: true
                visible: entityModel.count === 0
                wrapMode: Text.WordWrap
                text: i18n("Choose Discover devices and entities to load the available entities.")
            }

            Repeater {
                model: entityModel
                delegate: RowLayout {
                    required property string entityId
                    required property string name
                    required property string deviceId
                    required property string deviceName
                    required property string areaId
                    required property string areaName
                    required property string state

                    Layout.fillWidth: true
                    visible: root.matchesFilters({
                        areaId: areaId,
                        deviceId: deviceId
                    })

                    Controls.CheckBox {
                        id: entityCheckBox
                        Layout.fillWidth: true
                        text: name + " (" + entityId + ") — " + areaName + " / " + deviceName + ": " + state
                        checked: root.isEntitySelected(entityId)
                        onToggled: root.setEntitySelected(entityId, checked)
                    }

                    Controls.ToolButton {
                        visible: entityCheckBox.checked
                        enabled: root.canMoveSelectedEntity(entityId, -1)
                        text: "↑"
                        display: Controls.AbstractButton.TextOnly
                        Accessible.name: i18n("Move %1 up", name)
                        onClicked: root.moveSelectedEntity(entityId, -1)
                    }

                    Controls.ToolButton {
                        visible: entityCheckBox.checked
                        enabled: root.canMoveSelectedEntity(entityId, 1)
                        text: "↓"
                        display: Controls.AbstractButton.TextOnly
                        Accessible.name: i18n("Move %1 down", name)
                        onClicked: root.moveSelectedEntity(entityId, 1)
                    }

                    Controls.ToolButton {
                        visible: entityCheckBox.checked
                                 && root.isFirstSelectedEntityForDevice(entityId)
                        enabled: root.canMoveDeviceTile(entityId, -1)
                        text: "⇡"
                        display: Controls.AbstractButton.TextOnly
                        Accessible.name: i18n("Move %1 tile up", deviceName)
                        onClicked: root.moveDeviceTile(entityId, -1)
                    }

                    Controls.ToolButton {
                        visible: entityCheckBox.checked
                                 && root.isFirstSelectedEntityForDevice(entityId)
                        enabled: root.canMoveDeviceTile(entityId, 1)
                        text: "⇣"
                        display: Controls.AbstractButton.TextOnly
                        Accessible.name: i18n("Move %1 tile down", deviceName)
                        onClicked: root.moveDeviceTile(entityId, 1)
                    }
                }

            }
        }
    }

    FileDialog {
        id: backupFileDialog
        title: i18n("Select a Home Assistant widget backup")
        fileMode: FileDialog.OpenFile
        nameFilters: [i18n("JSON files (*.json)"), i18n("All files (*)")]
        onAccepted: root.loadBackupFile(selectedFile.toString())
    }

    BackupReader.BackupFileReader {
        id: backupFileReader
    }
}
