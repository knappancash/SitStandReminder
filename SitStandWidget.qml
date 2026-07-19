import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    layerNamespacePlugin: "sit-stand-reminder"
    popoutWidth: 440
    popoutHeight: 410 + recentHistory.length * 22
    readonly property string reminderToggleText: enabledState.value ? "Pause reminders" : "Enable reminders"
    readonly property string reminderToggleIcon: enabledState.value ? "pause" : "play_arrow"
    readonly property string popoutStatusText: {
        if (!enabledState.value || postureState.value === "unknown" || idleState.value || returnGraceState.value)
            return statusTextState.value;
        const current = postureLabel(postureState.value) + " for " + formatDuration(postureElapsedState.value);
        if (pendingTargetState.value)
            return current + " • " + postureLabel(pendingTargetState.value) + (snoozeUntilState.value > Date.now() ? " snoozed" : " overdue");
        return current + " • " + postureLabel(postureState.value === "sitting" ? "standing" : "sitting") + " in " + formatDuration(remainingSecondsState.value);
    }
    readonly property string todayTotalsText: "Sitting " + formatDuration(todaySittingState.value) + "  •  Standing " + formatDuration(todayStandingState.value)
    readonly property string standingTargetText: "Standing target: " + Math.min(100, Math.round(todayStandingState.value * 100 / Math.max(1, targetStandingState.value))) + "%"
    readonly property var recentHistory: {
        try {
            const history = JSON.parse(dailyHistoryJsonState.value);
            return Array.isArray(history) ? history.slice(-5).reverse() : [];
        } catch (error) {
            return [];
        }
    }

    function invoke(operation, argument) {
        const command = ["dms", "ipc", "call", "sitStandReminder", operation];
        if (argument !== undefined)
            command.push(String(argument));
        Quickshell.execDetached(command);
    }

    function formatDuration(seconds) {
        const safe = Math.max(0, Math.floor(seconds));
        const hours = Math.floor(safe / 3600);
        const minutes = Math.floor((safe % 3600) / 60);
        return hours > 0 ? hours + "h " + minutes + "m" : minutes + "m";
    }

    function postureLabel(value) {
        if (value === "sitting")
            return "Sitting";
        if (value === "standing")
            return "Standing";
        return "Not set";
    }

    function iconName() {
        if (!enabledState.value || idleState.value || returnGraceState.value)
            return "pause";
        if (postureState.value === "unknown")
            return "desk";
        if (overdueState.value)
            return "warning";
        return postureState.value === "sitting" ? "chair" : "accessibility_new";
    }

    function iconColor() {
        if (overdueState.value)
            return Theme.warning;
        return enabledState.value ? Theme.primary : Theme.surfaceVariantText;
    }

    function compactText() {
        if (!enabledState.value)
            return "Off";
        if (postureState.value === "unknown")
            return "Set posture";
        if (idleState.value || returnGraceState.value)
            return "Paused";
        if (pendingTargetState.value)
            return pendingTargetState.value === "standing" ? "Stand overdue" : "Sit overdue";
        return Math.max(0, Math.ceil(remainingSecondsState.value / 60)) + "m";
    }

    ccWidgetIcon: iconName()
    ccWidgetPrimaryText: "Sit/Stand"
    ccWidgetSecondaryText: statusTextState.value
    ccWidgetIsActive: enabledState.value
    onCcWidgetToggled: invoke("toggle")

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS
            DankIcon {
                name: root.iconName()
                size: root.iconSize
                color: root.iconColor()
                anchors.verticalCenter: parent.verticalCenter
            }
            StyledText {
                text: root.compactText()
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                color: root.iconColor()
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXS
            DankIcon {
                name: root.iconName()
                size: root.iconSize
                color: root.iconColor()
                anchors.horizontalCenter: parent.horizontalCenter
            }
            StyledText {
                text: root.pendingTargetState.value ? "!" : (root.postureState.value === "unknown" ? "?" : Math.max(0, Math.ceil(root.remainingSecondsState.value / 60)))
                font.pixelSize: Theme.fontSizeSmall
                color: root.iconColor()
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popout
            detailsText: root.popoutStatusText
            showCloseButton: false

            Column {
                width: parent.width
                spacing: Theme.spacingM

                Row {
                    id: enableRow
                    width: parent.width
                    spacing: Theme.spacingS
                    property real buttonWidth: (width - spacing) / 2
                    DankButton {
                        width: enableRow.buttonWidth
                        text: root.reminderToggleText
                        iconName: root.reminderToggleIcon
                        onClicked: root.invoke("toggle")
                    }
                    DankButton {
                        width: enableRow.buttonWidth
                        text: "Reset interval"
                        iconName: "refresh"
                        enabled: root.enabledState.value && root.postureState.value !== "unknown"
                        onClicked: root.invoke("reset")
                    }
                }

                StyledText {
                    text: "Confirm actual posture"
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                }
                Row {
                    id: postureButtons
                    width: parent.width
                    spacing: Theme.spacingS
                    property real buttonWidth: (width - spacing) / 2
                    DankButton {
                        width: postureButtons.buttonWidth
                        text: "I'm sitting"
                        iconName: "chair"
                        enabled: root.enabledState.value
                        onClicked: root.invoke("sit")
                    }
                    DankButton {
                        width: postureButtons.buttonWidth
                        text: "I'm standing"
                        iconName: "accessibility_new"
                        enabled: root.enabledState.value
                        onClicked: root.invoke("stand")
                    }
                }

                StyledRect {
                    width: parent.width
                    height: statsColumn.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    Column {
                        id: statsColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingXS
                        StyledText {
                            text: "Today"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                        }
                        StyledText {
                            text: root.todayTotalsText
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                        StyledText {
                            text: root.standingTargetText
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.primary
                        }
                    }
                }

                StyledRect {
                    width: parent.width
                    height: historyColumn.implicitHeight + Theme.spacingM * 2
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    Column {
                        id: historyColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingXS
                        StyledText {
                            text: "Recent days"
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                        }
                        StyledText {
                            visible: root.recentHistory.length === 0
                            text: "Completed days will appear here"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                        Repeater {
                            model: root.recentHistory
                            delegate: StyledText {
                                required property var modelData
                                width: historyColumn.width
                                text: modelData.date + "  Sitting " + root.formatDuration(modelData.sittingSeconds) + "  •  Standing " + root.formatDuration(modelData.standingSeconds)
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                        }
                    }
                }

            }
        }
    }

    ccDetailContent: Component {
        StyledRect {
            implicitHeight: ccColumn.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: Theme.surfaceContainerHigh
            Column {
                id: ccColumn
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                spacing: Theme.spacingS
                StyledText { text: root.statusTextState.value; color: Theme.surfaceText; font.pixelSize: Theme.fontSizeMedium }
                Row {
                    spacing: Theme.spacingS
                    DankButton { text: "Sitting"; iconName: "chair"; onClicked: root.invoke("sit") }
                    DankButton { text: "Standing"; iconName: "accessibility_new"; onClicked: root.invoke("stand") }
                }
            }
        }
    }
    ccDetailHeight: 130

    PluginGlobalVar { id: enabledState; varName: "enabled"; defaultValue: true }
    PluginGlobalVar { id: postureState; varName: "posture"; defaultValue: "unknown" }
    PluginGlobalVar { id: remainingSecondsState; varName: "remainingSeconds"; defaultValue: 0 }
    PluginGlobalVar { id: postureElapsedState; varName: "postureElapsedSeconds"; defaultValue: 0 }
    PluginGlobalVar { id: pendingTargetState; varName: "pendingTarget"; defaultValue: "" }
    PluginGlobalVar { id: overdueState; varName: "isOverdue"; defaultValue: false }
    PluginGlobalVar { id: snoozeUntilState; varName: "snoozeUntil"; defaultValue: 0 }
    PluginGlobalVar { id: idleState; varName: "isIdle"; defaultValue: false }
    PluginGlobalVar { id: returnGraceState; varName: "isInReturnGrace"; defaultValue: false }
    PluginGlobalVar { id: todaySittingState; varName: "todaySittingSeconds"; defaultValue: 0 }
    PluginGlobalVar { id: todayStandingState; varName: "todayStandingSeconds"; defaultValue: 0 }
    PluginGlobalVar { id: dailyHistoryJsonState; varName: "dailyHistoryJson"; defaultValue: "[]" }
    PluginGlobalVar { id: targetStandingState; varName: "dailyStandingTargetSeconds"; defaultValue: 7200 }
    PluginGlobalVar { id: statusTextState; varName: "statusText"; defaultValue: "Loading" }
}
