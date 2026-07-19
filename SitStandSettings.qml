import QtQuick
import Quickshell
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "sitStandReminder"
    property string armedReset: ""

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

    StyledText {
        width: parent.width
        text: "Sit/Stand Reminder"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }
    StyledText {
        width: parent.width
        text: "Evidence-informed defaults, not medical rules. Alternate positions, add light movement where possible, and adjust or stop if standing causes pain, dizziness, or other symptoms."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StyledText { text: "General"; font.pixelSize: Theme.fontSizeMedium; font.weight: Font.DemiBold; color: Theme.surfaceText }
    ToggleSetting { settingKey: "remindersEnabled"; label: "Enable reminders"; defaultValue: true }
    SliderSetting { settingKey: "sittingMinutes"; label: "Sitting duration"; description: "Time before requesting standing"; defaultValue: 30; minimum: 1; maximum: 240; unit: "min" }
    SliderSetting { settingKey: "standingMinutes"; label: "Standing duration"; description: "Time before requesting sitting"; defaultValue: 15; minimum: 1; maximum: 120; unit: "min" }
    SliderSetting { settingKey: "defaultSnoozeMinutes"; label: "Notification snooze"; description: "Single delay offered by transition notifications"; defaultValue: 10; minimum: 1; maximum: 60; unit: "min" }
    SliderSetting { settingKey: "dailyStandingTargetMinutes"; label: "Daily standing target"; defaultValue: 120; minimum: 5; maximum: 480; unit: "min" }
    SliderSetting { settingKey: "stalenessHours"; label: "Posture staleness"; description: "Ask again after a long pause or restart gap"; defaultValue: 12; minimum: 1; maximum: 48; unit: "h" }

    StyledText { text: "Reminder behaviour"; font.pixelSize: Theme.fontSizeMedium; font.weight: Font.DemiBold; color: Theme.surfaceText }
    SliderSetting { settingKey: "reminderRepeatMinutes"; label: "Reminder repeat interval"; defaultValue: 10; minimum: 1; maximum: 60; unit: "min" }
    SliderSetting { settingKey: "maximumAutomaticRepeats"; label: "Maximum automatic repeats"; defaultValue: 3; minimum: 0; maximum: 10 }
    SliderSetting { settingKey: "returnGraceSeconds"; label: "Return grace period"; defaultValue: 60; minimum: 0; maximum: 600; unit: "s" }
    ToggleSetting { settingKey: "actionableNotifications"; label: "Actionable notifications"; description: "Falls back to ordinary notifications when unsupported"; defaultValue: true }

    StyledText { text: "Idle behaviour"; font.pixelSize: Theme.fontSizeMedium; font.weight: Font.DemiBold; color: Theme.surfaceText }
    ToggleSetting { settingKey: "pauseWhileIdle"; label: "Pause while idle"; description: "Uses inhibitor-aware Wayland idle monitoring"; defaultValue: true }
    SliderSetting { settingKey: "idleThresholdSeconds"; label: "Idle threshold"; defaultValue: 300; minimum: 30; maximum: 3600; unit: "s" }
    ToggleSetting { settingKey: "countIdleTime"; label: "Count idle time in statistics"; description: "Off by default because posture is unknown while away"; defaultValue: false }

    StyledText { text: "Data"; font.pixelSize: Theme.fontSizeMedium; font.weight: Font.DemiBold; color: Theme.surfaceText }
    StyledText {
        width: parent.width
        text: "Destructive actions require a second click within five seconds."
        color: Theme.surfaceVariantText
        font.pixelSize: Theme.fontSizeSmall
    }
    Row {
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
