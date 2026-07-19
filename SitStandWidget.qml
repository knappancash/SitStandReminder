import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "SitStandMath.js" as SitStandMath

PluginComponent {
    id: root

    pluginId: "sitStandReminder"
    pluginService: PluginService
    layerNamespacePlugin: "sit-stand-reminder"
    popoutWidth: 440
    popoutHeight: 410 + (recentHistory.length > 0 ? 165 : 0)
    property int historyRange: 7
    readonly property string reminderToggleText: enabledState.value ? "Pause reminders" : "Enable reminders"
    readonly property string reminderToggleIcon: enabledState.value ? "pause" : "play_arrow"
    readonly property string popoutStatusText: {
        if (!enabledState.value)
            return postureState.value === "unknown" ? "Disabled" : "Disabled • Was " + postureState.value + " for " + formatDuration(postureElapsedState.value);
        if (postureState.value === "unknown" || idleState.value || returnGraceState.value)
            return statusTextState.value;
        if (standingTargetReachedState.value)
            return postureLabel(postureState.value) + " for " + formatDuration(postureElapsedState.value) + " • Standing target reached";
        const current = postureLabel(postureState.value) + " for " + formatDuration(postureElapsedState.value);
        if (pendingTargetState.value)
            return current + " • " + postureLabel(pendingTargetState.value) + (snoozeUntilState.value > Date.now() ? " snoozed" : " overdue");
        return current + " • " + postureLabel(postureState.value === "sitting" ? "standing" : "sitting") + " in " + formatDuration(SitStandMath.ceilToMinute(remainingSecondsState.value));
    }
    readonly property string todayTotalsText: "Sitting " + formatDuration(todaySittingState.value) + "  •  Standing " + formatDuration(todayStandingState.value)
    readonly property string standingTargetText: "Standing target: " + Math.min(100, Math.round(todayStandingState.value * 100 / Math.max(1, targetStandingState.value))) + "% (" + formatDuration(targetStandingState.value).replace(" 0m", "") + ")"
    readonly property var recentHistory: {
        try {
            const history = JSON.parse(dailyHistoryJsonState.value);
            return Array.isArray(history) ? history.slice(-30) : [];
        } catch (error) {
            return [];
        }
    }
    readonly property var historyChart: SitStandMath.historyChart(recentHistory, historyRange)

    function invoke(operation, argument) {
        const daemon = pluginService && pluginService.pluginDaemonInstances ? pluginService.pluginDaemonInstances[pluginId] : null;
        if (daemon) {
            if (operation === "toggle") {
                daemon.setEnabled(!daemon.remindersEnabled);
                return;
            }
            if (operation === "reset") {
                daemon.resetCurrentInterval();
                return;
            }
            if (operation === "sit") {
                daemon.confirmPosture("sitting");
                return;
            }
            if (operation === "stand") {
                daemon.confirmPosture("standing");
                return;
            }
        }
        const command = ["dms", "ipc", "call", "sitStandReminder", operation];
        if (argument !== undefined)
            command.push(String(argument));
        Quickshell.execDetached(command);
    }

    function cycleHistoryRange() {
        historyRange = SitStandMath.nextHistoryRange(historyRange);
    }

    function formatDuration(seconds) {
        const safe = Math.max(0, Math.floor(seconds));
        const hours = Math.floor(safe / 3600);
        const minutes = Math.floor((safe % 3600) / 60);
        return hours > 0 ? hours + "h " + minutes + "m" : minutes + "m";
    }

    function formatHistoryDate(value) {
        const locale = I18n.locale();
        return new Date(value + "T12:00:00").toLocaleDateString(locale, SitStandMath.dateFormatWithoutYear(locale.dateFormat(Locale.ShortFormat)));
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
        if (!enabledState.value || idleState.value || returnGraceState.value)
            return Theme.surfaceVariantText;
        if (overdueState.value)
            return Theme.warning;
        return Theme.primary;
    }

    function compactText() {
        if (!enabledState.value)
            return "Off";
        if (postureState.value === "unknown")
            return "Set posture";
        if (idleState.value || returnGraceState.value)
            return "Paused";
        if (standingTargetReachedState.value)
            return "Goal met";
        if (pendingTargetState.value)
            return pendingTargetState.value === "standing" ? "Stand overdue" : "Sit overdue";
        return Math.max(0, Math.ceil(remainingSecondsState.value / 60)) + "m";
    }

    ccWidgetIcon: iconName()
    ccWidgetPrimaryText: "Sit/Stand"
    ccWidgetSecondaryText: statusTextState.value
    ccWidgetIsActive: enabledState.value && postureState.value === "standing"
    onCcWidgetToggled: {
        if (enabledState.value)
            invoke(SitStandMath.postureToggleOperation(postureState.value));
    }

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
                text: root.standingTargetReachedState.value ? "\u2713" : (root.pendingTargetState.value ? "!" : (root.postureState.value === "unknown" ? "?" : Math.max(0, Math.ceil(root.remainingSecondsState.value / 60))))
                font.pixelSize: Theme.fontSizeSmall
                color: root.iconColor()
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            id: popout
            topPadding: Theme.spacingXS
            detailsText: root.popoutStatusText
            showCloseButton: false

            Column {
                width: parent.width
                spacing: Theme.spacingS

                Row {
                    id: enableRow
                    x: Theme.spacingM
                    width: parent.width - Theme.spacingM * 2
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
                    leftPadding: Theme.spacingM
                    text: "Select your current posture"
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                }
                Row {
                    id: postureButtons
                    x: Theme.spacingM
                    width: parent.width - Theme.spacingM * 2
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
                    height: statsColumn.implicitHeight + Theme.spacingM + Theme.spacingS
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    Column {
                        id: statsColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        anchors.bottomMargin: Theme.spacingS
                        spacing: Theme.spacingXS
                        Row {
                            width: parent.width
                            StyledText {
                                id: todayTitle
                                text: "Today"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                            }
                            StyledText {
                                width: parent.width - x
                                anchors.baseline: todayTitle.baseline
                                text: root.standingTargetText
                                horizontalAlignment: Text.AlignRight
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.primary
                            }
                        }
                        StyledText {
                            text: root.todayTotalsText
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }
                }

                StyledRect {
                    width: parent.width
                    height: historyColumn.implicitHeight + Theme.spacingM + Theme.spacingS
                    radius: Theme.cornerRadius
                    color: Theme.surfaceContainerHigh
                    Column {
                        id: historyColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        anchors.topMargin: Theme.spacingS
                        spacing: Theme.spacingXS
                        Row {
                            width: parent.width
                            StyledText {
                                id: historyTitle
                                text: "History"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                            }
                            StyledText {
                                width: parent.width - x
                                anchors.baseline: historyTitle.baseline
                                text: root.historyRange + " days"
                                horizontalAlignment: Text.AlignRight
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.primary
                            }
                        }
                        StyledText {
                            visible: root.recentHistory.length === 0
                            text: "Completed days will appear here"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                        Row {
                            visible: root.recentHistory.length > 0
                            spacing: Theme.spacingM
                            Row {
                                spacing: Theme.spacingXS
                                Rectangle {
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: Theme.secondary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    text: "Sitting avg " + root.formatDuration(root.historyChart.sittingAverage)
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }
                            }
                            Row {
                                spacing: Theme.spacingXS
                                Rectangle {
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: Theme.primary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                StyledText {
                                    text: "Standing avg " + root.formatDuration(root.historyChart.standingAverage)
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                }
                            }
                        }
                        Item {
                            width: historyColumn.width
                            height: root.recentHistory.length > 0 ? 130 : 0
                            visible: root.recentHistory.length > 0
                            Accessible.name: root.historyChart.days.map(day => root.formatHistoryDate(day.date) + ", sitting " + root.formatDuration(day.sittingSeconds) + ", standing " + root.formatDuration(day.standingSeconds)).join("; ")

                            Canvas {
                                id: historyGraph
                                width: parent.width
                                height: 105
                                renderStrategy: Canvas.Cooperative
                                property var sitting: root.historyChart.sitting
                                property var standing: root.historyChart.standing
                                property real maximum: root.historyChart.maximum
                                property int hoveredIndex: -1
                                property int hoveredSeries: -1

                                onSittingChanged: requestPaint()
                                onStandingChanged: requestPaint()
                                onMaximumChanged: requestPaint()
                                onWidthChanged: requestPaint()
                                onHeightChanged: requestPaint()

                                function pointX(index) {
                                    return (index + 0.5) * width / sitting.length;
                                }

                                function pointY(value) {
                                    return height - 4 - value / maximum * (height - 8);
                                }

                                function drawSeries(context, values, color) {
                                    if (values.length === 0)
                                        return;
                                    context.strokeStyle = color;
                                    context.fillStyle = color;
                                    context.lineWidth = 2;
                                    context.beginPath();
                                    values.forEach((value, index) => {
                                        const x = pointX(index);
                                        const y = pointY(value);
                                        index === 0 ? context.moveTo(x, y) : context.lineTo(x, y);
                                    });
                                    context.stroke();
                                    values.forEach((value, index) => {
                                        const x = pointX(index);
                                        const y = pointY(value);
                                        context.beginPath();
                                        context.arc(x, y, 3, 0, Math.PI * 2);
                                        context.fill();
                                    });
                                }

                                onPaint: {
                                    const context = getContext("2d");
                                    context.reset();
                                    context.clearRect(0, 0, width, height);
                                    context.strokeStyle = Theme.withAlpha(Theme.surfaceVariantText, 0.15);
                                    context.lineWidth = 1;
                                    [0, height / 2, height - 1].forEach(y => {
                                        context.beginPath();
                                        context.moveTo(0, y);
                                        context.lineTo(width, y);
                                        context.stroke();
                                    });
                                    drawSeries(context, sitting, Theme.secondary);
                                    drawSeries(context, standing, Theme.primary);
                                }
                            }
                            MouseArea {
                                x: historyGraph.x
                                width: historyGraph.width
                                height: historyGraph.height
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onPositionChanged: mouse => {
                                    const nearest = SitStandMath.nearestChartPoint(historyGraph.sitting, historyGraph.standing, historyGraph.maximum, width, height, mouse.x, mouse.y, 12);
                                    historyGraph.hoveredIndex = nearest ? nearest.index : -1;
                                    historyGraph.hoveredSeries = nearest ? nearest.series : -1;
                                }
                                onExited: {
                                    historyGraph.hoveredIndex = -1;
                                    historyGraph.hoveredSeries = -1;
                                }
                                onClicked: {
                                    historyGraph.hoveredIndex = -1;
                                    historyGraph.hoveredSeries = -1;
                                    root.cycleHistoryRange();
                                }
                            }
                            StyledRect {
                                readonly property real hoveredValue: historyGraph.hoveredIndex < 0 ? 0 : (historyGraph.hoveredSeries === 0 ? historyGraph.sitting[historyGraph.hoveredIndex] : historyGraph.standing[historyGraph.hoveredIndex])
                                visible: historyGraph.hoveredIndex >= 0
                                z: 2
                                width: hoverText.implicitWidth + Theme.spacingM * 2
                                height: hoverText.implicitHeight + Theme.spacingS * 2
                                x: historyGraph.hoveredIndex < 0 ? 0 : Math.max(historyGraph.x, Math.min(parent.width - width, historyGraph.x + historyGraph.pointX(historyGraph.hoveredIndex) - width / 2))
                                y: historyGraph.hoveredIndex < 0 ? 0 : Math.max(0, historyGraph.pointY(hoveredValue) - height - Theme.spacingXS)
                                radius: Theme.cornerRadius
                                color: Theme.surfaceContainerHighest
                                StyledText {
                                    id: hoverText
                                    anchors.centerIn: parent
                                    text: historyGraph.hoveredIndex < 0 ? "" : root.formatHistoryDate(root.historyChart.days[historyGraph.hoveredIndex].date) + " • " + (historyGraph.hoveredSeries === 0 ? "Sitting " : "Standing ") + root.formatDuration(parent.hoveredValue)
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: historyGraph.hoveredSeries === 0 ? Theme.secondary : Theme.primary
                                }
                            }
                            Item {
                                id: dateLabels
                                x: historyGraph.x
                                y: historyGraph.height + Theme.spacingXS
                                width: historyGraph.width
                                height: Theme.fontSizeSmall + Theme.spacingXS
                                Repeater {
                                    model: root.historyChart.labels
                                    StyledText {
                                        required property var modelData
                                        x: Math.max(0, Math.min(dateLabels.width - width, historyGraph.pointX(modelData.index) - width / 2))
                                        text: root.formatHistoryDate(modelData.date)
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                    }
                                }
                            }
                        }
                    }
                }

            }
        }
    }

    ccDetailContent: popoutContent
    ccDetailHeight: recentHistory.length > 0 ? 420 : 240

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
    PluginGlobalVar { id: standingTargetReachedState; varName: "standingTargetReached"; defaultValue: false }
    PluginGlobalVar { id: dailyHistoryJsonState; varName: "dailyHistoryJson"; defaultValue: "[]" }
    PluginGlobalVar { id: targetStandingState; varName: "dailyStandingTargetSeconds"; defaultValue: 7200 }
    PluginGlobalVar { id: statusTextState; varName: "statusText"; defaultValue: "Set current posture" }
}
