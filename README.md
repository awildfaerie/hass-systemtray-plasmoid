# Home Assistant Plasmoid

A KDE Plasma system-tray widget for controlling Home Assistant entities.

This repository contains a Plasma 6 system-tray applet. Its configuration
dialog discovers devices and entities, and the popup displays live statuses
and controls for the selected entities, including camera streams.

## Build and install

The widget is a Plasma 6 system-tray applet, added from the system tray's
**Entries** settings rather than as a standalone panel widget. Building
requires CMake and the Qt 6 Core and QML development libraries for the local
backup-file reader. At runtime, the configuration dialog requires the Qt 6
WebSockets and Quick Dialogs QML modules, and camera playback requires the Qt 6
WebEngine QML module.

**Debian / Ubuntu**

```sh
sudo apt install cmake qt6-base-dev qt6-declarative-dev \
    qml6-module-qtwebsockets qml6-module-qtquick-dialogs \
    qml6-module-qtwebengine
```

**Fedora**

```sh
sudo dnf install cmake qt6-qtbase-devel qt6-qtdeclarative-devel \
    qt6-qtwebsockets qt6-qtwebengine
```

**Arch Linux**

```sh
sudo pacman -S --needed cmake qt6-base qt6-declarative \
    qt6-websockets qt6-webengine
```

**openSUSE Tumbleweed**

```sh
sudo zypper install cmake qt6-base-devel qt6-declarative-devel \
    qt6-declarative-imports qt6-websockets-imports qt6-webengine-imports
```

Build and install the applet and its local backup-file reader with CMake:

```sh
cmake -S . -B build -DCMAKE_INSTALL_PREFIX="$HOME/.local"
cmake --build build
cmake --install build
```

To remove the CMake installation:

```sh
rm -r "$HOME/.local/share/plasma/plasmoids/org.kde.plasma.homeassistant"
```

After installation, open **System Tray Settings → Entries** and set **Home
Assistant** to **Shown** or **Always shown**. The applet may not appear in the
general **Add Widgets** dialog because Plasma treats it as a system-tray entry.
If it is missing, restart Plasma Shell or log out and back in.

## Configure

Open the system-tray widget's context menu and choose **Configure Home
Assistant**. Enter the server URL and a Home Assistant long-lived access token,
then apply the settings. When both credentials are saved, opening the
configuration page automatically discovers devices and entities. Use
**Discover devices and entities** to retry or refresh discovery. Filter by area
and/or device using the dropdown menus. The area filter defaults to **All
areas**; the device filter defaults to **All devices** and lists devices
associated with the selected area. **Select all** and **Clear selection**
apply to the currently filtered entities. Apply the settings to save the
selected entity IDs.

Use **Copy backup** to copy a JSON backup to the clipboard, then save it in a
secure location. To restore it, choose **Load backup file…** and select the
saved JSON file, then apply the settings. Backups include the server URL,
access token, selected entities, and device tile order. The access token is
stored in the backup as plain text; protect the file accordingly.

The access token is stored unencrypted in the widget's local configuration.
Use a dedicated Home Assistant account with permission to read states and
device/entity registries, and use HTTPS when connecting over an untrusted
network. If registry access is denied, the widget still lists available
entities but cannot group them by device.

The popup currently supports camera entities with a **View stream** toggle
that opens Home Assistant's authenticated MJPEG camera proxy in a separate
window. Camera playback requires the entity to expose a camera access token.

The popup also supports on/off controls for lights, switches, fans,
humidifiers, sirens, water heaters, covers, and media players; numeric values
for `input_number`; brightness, fan percentage, media volume, and cover
position sliders; climate temperature dials; and press/run/activate buttons for
buttons, input buttons, scripts, and scenes. Other selected entities are shown
with status only.

Selected entities are arranged in a responsive masonry-style grid of device
tiles, without area headings. Tiles move into the shortest available column
and reflow as the view is resized. Entities without a device are grouped
together in an **Other entities** tile. In the configuration page, use the
entity up/down arrows to set order within a tile, and the device tile arrows
to set the global tile order.
