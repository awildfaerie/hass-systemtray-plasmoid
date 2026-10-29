cmake_minimum_required(VERSION 3.16)

project(hass-plasmoid)

include(GNUInstallDirs)
find_package(Qt6 6.2 REQUIRED COMPONENTS Core Qml)
set(CMAKE_AUTOMOC ON)

install(DIRECTORY package/
    DESTINATION "${CMAKE_INSTALL_DATADIR}/plasma/plasmoids/org.kde.plasma.homeassistant"
)

add_library(backupreaderplugin MODULE
    src/backupfilereader.cpp
    src/backupreaderplugin.cpp
)
target_link_libraries(backupreaderplugin PRIVATE Qt6::Core Qt6::Qml)
set_target_properties(backupreaderplugin PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/qml/HomeAssistant/BackupReader"
)

install(TARGETS backupreaderplugin
    LIBRARY DESTINATION
        "${CMAKE_INSTALL_DATADIR}/plasma/plasmoids/org.kde.plasma.homeassistant/contents/ui/HomeAssistant/BackupReader"
)
