import QtQuick
import Quickshell
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "sitStandReminder"
    property string armedReset: ""
    property int currentTab: 0

    function invoke(operation) {
        Quickshell.execDetached(["dms", "ipc", "call", "sitStandReminder", operation]);
    }

    function confirmReset(operation) {
        if (armedReset === operation) {
            armedReset = "";
            invoke(operation);
        } else {
            armedReset = operation;
            resetConfirmationTimer.restart();
        }
    }

    Timer {
        id: resetConfirmationTimer
        interval: 5000
        onTriggered: root.armedReset = ""
    }

    ToggleSetting { settingKey: "remindersEnabled"; label: "Enable reminders"; defaultValue: true }

    Item {
        width: parent.width
        height: settingsTabs.height + Theme.spacingM

        DankTabBar {
            id: settingsTabs
            width: parent.width
            tabHeight: 44
            spacing: Theme.spacingS
            showIcons: false
            currentIndex: root.currentTab
            model: [{ text: "Timing" }, { text: "Reminders" }, { text: "Idle" }, { text: "Data" }]
            onTabClicked: index => root.currentTab = index
            Component.onCompleted: Qt.callLater(updateIndicator)
        }
    }
    SliderSetting { visible: root.currentTab === 0; settingKey: "sittingMinutes"; label: "Sitting duration"; description: "Time before requesting standing"; defaultValue: 30; minimum: 1; maximum: 240; unit: "min" }
    SliderSetting { visible: root.currentTab === 0; settingKey: "standingMinutes"; label: "Standing duration"; description: "Time before requesting sitting"; defaultValue: 15; minimum: 1; maximum: 120; unit: "min" }
    SliderSetting { visible: root.currentTab === 0; settingKey: "defaultSnoozeMinutes"; label: "Notification snooze"; description: "Single delay offered by transition notifications"; defaultValue: 10; minimum: 1; maximum: 60; unit: "min" }
    SliderSetting { visible: root.currentTab === 0; settingKey: "dailyStandingTargetMinutes"; label: "Daily standing target"; defaultValue: 120; minimum: 5; maximum: 480; unit: "min" }

    SliderSetting { visible: root.currentTab === 1; settingKey: "reminderRepeatMinutes"; label: "Reminder repeat interval"; defaultValue: 10; minimum: 1; maximum: 60; unit: "min" }
    SliderSetting { visible: root.currentTab === 1; settingKey: "maximumAutomaticRepeats"; label: "Maximum automatic repeats"; defaultValue: 3; minimum: 0; maximum: 10 }
    ToggleSetting { visible: root.currentTab === 1; settingKey: "actionableNotifications"; label: "Actionable notifications"; description: "Falls back to ordinary notifications when unsupported"; defaultValue: true }
    SliderSetting { visible: root.currentTab === 1; settingKey: "stalenessHours"; label: "Posture staleness"; description: "Ask again after a long pause or restart gap"; defaultValue: 12; minimum: 1; maximum: 48; unit: "h" }

    ToggleSetting { visible: root.currentTab === 2; settingKey: "pauseWhileIdle"; label: "Pause while idle"; description: "Uses inhibitor-aware Wayland idle monitoring"; defaultValue: true }
    SliderSetting { visible: root.currentTab === 2; settingKey: "idleThresholdSeconds"; label: "Idle threshold"; defaultValue: 300; minimum: 30; maximum: 3600; unit: "s" }
    SliderSetting { visible: root.currentTab === 2; settingKey: "returnGraceSeconds"; label: "Return grace period"; defaultValue: 60; minimum: 0; maximum: 600; unit: "s" }
    ToggleSetting { visible: root.currentTab === 2; settingKey: "countIdleTime"; label: "Count idle time in statistics"; description: "Off by default because posture is unknown while away"; defaultValue: false }

    SliderSetting { visible: root.currentTab === 3; settingKey: "dayStartHour"; label: "Next day delay"; description: "Hours after midnight before daily statistics reset"; defaultValue: 0; minimum: 0; maximum: 12; unit: "h" }
    StyledText {
        visible: root.currentTab === 3
        text: "Reset actions require a second click within five seconds."
        color: Theme.surfaceVariantText
        font.pixelSize: Theme.fontSizeSmall
    }
    Flow {
        visible: root.currentTab === 3
        width: parent.width
        spacing: Theme.spacingS
        DankButton {
            text: root.armedReset === "resetSession" ? "Click again" : "Reset session"
            onClicked: root.confirmReset("resetSession")
        }
        DankButton {
            text: root.armedReset === "resetToday" ? "Click again" : "Reset today"
            onClicked: root.confirmReset("resetToday")
        }
        DankButton {
            text: root.armedReset === "resetAll" ? "Click again" : "Reset all state"
            onClicked: root.confirmReset("resetAll")
        }
    }
}
