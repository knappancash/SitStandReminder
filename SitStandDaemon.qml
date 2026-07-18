import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "SitStandMath.js" as SitStandMath

PluginComponent {
    id: root

    readonly property int minute: 60000
    readonly property int historyDays: 30
    property bool initialized: false
    property bool remindersEnabled: true
    property string posture: "unknown"
    property double postureStartedAt: 0
    property double dueAt: 0
    property double pausedMillis: 0
    property string pendingTarget: ""
    property bool isOverdue: false
    property double originalTargetDueAt: 0
    property double snoozeUntil: 0
    property double lastNotificationAt: 0
    property int reminderCount: 0
    property string currentDate: ""
    property double todaySittingSeconds: 0
    property double todayStandingSeconds: 0
    property var dailyHistory: []
    property double lastStateUpdateAt: 0
    property bool isIdle: false
    property double idleStartedAt: 0
    property double graceUntil: 0
    property double disabledAt: 0
    property double lastTickAt: 0
    property int periodicSaveTicks: 0
    property int appliedSittingMinutes: 30
    property int appliedStandingMinutes: 15

    property bool notifyAvailable: false
    property bool notificationActionsSupported: false
    property var notificationProcess: null
    property var queuedNotification: null
    property int notificationGeneration: 0

    readonly property bool configuredEnabled: pluginData.enabled ?? true
    readonly property int sittingMinutes: settingInt("sittingMinutes", 30, 1, 240)
    readonly property int standingMinutes: settingInt("standingMinutes", 15, 1, 120)
    readonly property int defaultSnoozeMinutes: settingInt("defaultSnoozeMinutes", 10, 1, 60)
    readonly property int dailyStandingTargetMinutes: settingInt("dailyStandingTargetMinutes", 120, 5, 480)
    readonly property int reminderRepeatMinutes: settingInt("reminderRepeatMinutes", 10, 1, 60)
    readonly property int maximumAutomaticRepeats: settingInt("maximumAutomaticRepeats", 3, 0, 10)
    readonly property int returnGraceSeconds: settingInt("returnGraceSeconds", 60, 0, 600)
    readonly property bool actionableNotifications: pluginData.actionableNotifications ?? true
    readonly property bool pauseWhileIdle: pluginData.pauseWhileIdle ?? true
    readonly property int idleThresholdSeconds: settingInt("idleThresholdSeconds", 300, 30, 3600)
    readonly property bool countIdleTime: pluginData.countIdleTime ?? false
    readonly property int stalenessHours: settingInt("stalenessHours", 12, 1, 48)

    function settingInt(key, fallback, minimum, maximum) {
        return Math.round(SitStandMath.clampNumber(pluginData[key], fallback, minimum, maximum));
    }

    function finite(value, fallback) {
        const number = Number(value);
        return Number.isFinite(number) ? number : fallback;
    }

    function validPosture(value) {
        return value === "sitting" || value === "standing" ? value : "unknown";
    }

    function validTarget(value) {
        return value === "sitting" || value === "standing" ? value : "";
    }

    function durationFor(postureName) {
        return (postureName === "sitting" ? sittingMinutes : standingMinutes) * minute;
    }

    function opposite(postureName) {
        return postureName === "sitting" ? "standing" : "sitting";
    }

    function tryInitialize() {
        if (initialized || !pluginService || !pluginId)
            return;

        const now = Date.now();
        ensureStateWriter();
        const saved = pluginService.loadPluginState(pluginId, "runtime", {});
        const state = saved && typeof saved === "object" ? saved : {};
        remindersEnabled = configuredEnabled;
        posture = validPosture(state.posture);
        postureStartedAt = finite(state.postureStartedAt, 0);
        dueAt = finite(state.dueAt, 0);
        pausedMillis = Math.max(0, finite(state.pausedMillis, 0));
        pendingTarget = validTarget(state.pendingTarget);
        isOverdue = Boolean(state.isOverdue && pendingTarget);
        originalTargetDueAt = finite(state.originalTargetDueAt, dueAt);
        snoozeUntil = finite(state.snoozeUntil, 0);
        lastNotificationAt = finite(state.lastNotificationAt, 0);
        reminderCount = Math.max(0, Math.round(finite(state.reminderCount, 0)));
        currentDate = typeof state.currentDate === "string" ? state.currentDate : SitStandMath.dateKey(now);
        todaySittingSeconds = Math.max(0, finite(state.todaySittingSeconds, 0));
        todayStandingSeconds = Math.max(0, finite(state.todayStandingSeconds, 0));
        dailyHistory = SitStandMath.normalizeHistory(state.dailyHistoryJson ?? state.dailyHistory, historyDays);
        lastStateUpdateAt = finite(state.lastStateUpdateAt, now);
        const persistedUpdateAt = lastStateUpdateAt;
        disabledAt = finite(state.disabledAt, 0);
        appliedSittingMinutes = Math.round(SitStandMath.clampNumber(state.appliedSittingMinutes, sittingMinutes, 1, 240));
        appliedStandingMinutes = Math.round(SitStandMath.clampNumber(state.appliedStandingMinutes, standingMinutes, 1, 120));

        const savedIdleStart = state.isIdle ? finite(state.idleStartedAt, now) : 0;
        if (savedIdleStart > 0 && now > savedIdleStart) {
            pauseDeadline(now - savedIdleStart);
            graceUntil = now + returnGraceSeconds * 1000;
            lastStateUpdateAt = now;
        }
        isIdle = false;
        idleStartedAt = 0;

        if (posture !== "unknown" && (postureStartedAt <= 0 || now - Math.max(persistedUpdateAt, postureStartedAt) > stalenessHours * 60 * minute))
            makeUnknown(now);
        else if (posture !== "unknown") {
            if (dueAt <= 0)
                dueAt = postureStartedAt + durationFor(posture) + pausedMillis;
            if (!state.isIdle && now - persistedUpdateAt > idleThresholdSeconds * 1000) {
                // ponytail: a long offline gap is treated as away; add logind suspend signals only if that distinction matters.
                pauseDeadline(now - persistedUpdateAt);
                graceUntil = now + returnGraceSeconds * 1000;
                lastStateUpdateAt = now;
            }
        }

        initialized = true;
        lastTickAt = now;
        accountTo(now);
        if ((posture === "sitting" && appliedSittingMinutes !== sittingMinutes) || (posture === "standing" && appliedStandingMinutes !== standingMinutes)) {
            appliedSittingMinutes = sittingMinutes;
            appliedStandingMinutes = standingMinutes;
            recalculateDue();
        } else {
            appliedSittingMinutes = sittingMinutes;
            appliedStandingMinutes = standingMinutes;
            evaluate(now);
            publish(now);
        }
        persist();
    }

    function stateObject() {
        return {
            posture: posture,
            postureStartedAt: postureStartedAt,
            dueAt: dueAt,
            pausedMillis: pausedMillis,
            pendingTarget: pendingTarget,
            isOverdue: isOverdue,
            originalTargetDueAt: originalTargetDueAt,
            snoozeUntil: snoozeUntil,
            lastNotificationAt: lastNotificationAt,
            reminderCount: reminderCount,
            currentDate: currentDate,
            todaySittingSeconds: Math.floor(todaySittingSeconds),
            todayStandingSeconds: Math.floor(todayStandingSeconds),
            dailyHistoryJson: JSON.stringify(dailyHistory),
            lastStateUpdateAt: lastStateUpdateAt,
            isIdle: isIdle,
            idleStartedAt: idleStartedAt,
            disabledAt: disabledAt,
            appliedSittingMinutes: appliedSittingMinutes,
            appliedStandingMinutes: appliedStandingMinutes
        };
    }

    function ensureStateWriter() {
        // DMS 1.5.1 drops its FileView on hot reload but keeps the cache marked loaded.
        if (pluginService && pluginService._stateWriters && !pluginService._stateWriters[pluginId] && pluginService._loadStateFromDisk)
            pluginService._loadStateFromDisk(pluginId);
    }

    function persist() {
        if (initialized && pluginService) {
            ensureStateWriter();
            pluginService.savePluginState(pluginId, "runtime", stateObject());
        }
    }

    function addPostureSeconds(seconds) {
        if (posture === "sitting")
            todaySittingSeconds += seconds;
        else if (posture === "standing")
            todayStandingSeconds += seconds;
    }

    function archiveCurrentDay() {
        if (currentDate && todaySittingSeconds + todayStandingSeconds > 0)
            dailyHistory = SitStandMath.recordDay(dailyHistory, currentDate, todaySittingSeconds, todayStandingSeconds, historyDays);
    }

    function accountTo(now) {
        if (!lastStateUpdateAt || lastStateUpdateAt > now)
            lastStateUpdateAt = now;

        const today = SitStandMath.dateKey(now);
        let start = lastStateUpdateAt;
        const shouldCount = remindersEnabled && posture !== "unknown" && (!isIdle || countIdleTime);
        if (currentDate !== today) {
            const split = SitStandMath.splitAtDayBoundary(start, now);
            if (shouldCount)
                addPostureSeconds(split.previousSeconds);
            archiveCurrentDay();
            currentDate = today;
            todaySittingSeconds = 0;
            todayStandingSeconds = 0;
            if (shouldCount)
                addPostureSeconds(split.currentSeconds);
            lastStateUpdateAt = now;
            return;
        }

        if (shouldCount)
            addPostureSeconds(Math.max(0, now - start) / 1000);
        lastStateUpdateAt = now;
    }

    function pauseDeadline(duration) {
        if (duration <= 0 || posture === "unknown")
            return;
        dueAt += duration;
        pausedMillis += duration;
        if (originalTargetDueAt > 0)
            originalTargetDueAt += duration;
        if (snoozeUntil > 0)
            snoozeUntil += duration;
    }

    function handleIdleChanged(idle) {
        if (!initialized || !pauseWhileIdle || idle === isIdle)
            return;
        const now = Date.now();
        accountTo(now);
        if (idle) {
            isIdle = true;
            idleStartedAt = now;
            closeNotification();
        } else {
            const paused = Math.max(0, now - idleStartedAt);
            isIdle = false;
            idleStartedAt = 0;
            pauseDeadline(paused);
            graceUntil = now + returnGraceSeconds * 1000;
        }
        publish(now);
        persist();
    }

    function handleClockGap(now) {
        if (!lastTickAt)
            return;
        const gap = now - lastTickAt;
        if (gap < -5000) {
            if (postureStartedAt > 0)
                postureStartedAt += gap;
            if (dueAt > 0)
                dueAt += gap;
            if (originalTargetDueAt > 0)
                originalTargetDueAt += gap;
            if (snoozeUntil > 0)
                snoozeUntil += gap;
            if (lastNotificationAt > 0)
                lastNotificationAt += gap;
            lastStateUpdateAt = now;
        } else if (gap > idleThresholdSeconds * 1000 && !isIdle) {
            accountTo(lastTickAt);
            lastStateUpdateAt = now;
            accountTo(now);
            pauseDeadline(gap);
            graceUntil = now + returnGraceSeconds * 1000;
            closeNotification();
            persist();
        }
    }

    function evaluate(now) {
        if (!initialized || !remindersEnabled || posture === "unknown" || isIdle || now < graceUntil)
            return;

        if (!pendingTarget && now >= dueAt) {
            pendingTarget = opposite(posture);
            isOverdue = true;
            originalTargetDueAt = dueAt;
            snoozeUntil = 0;
            reminderCount = 0;
            sendDeadlineNotification();
            lastNotificationAt = now;
            persist();
            return;
        }

        if (!pendingTarget)
            return;
        isOverdue = now >= originalTargetDueAt;
        if (snoozeUntil > 0) {
            if (now < snoozeUntil)
                return;
            snoozeUntil = 0;
            sendDeadlineNotification();
            lastNotificationAt = now;
            persist();
            return;
        }
        if (lastNotificationAt > 0 && now - lastNotificationAt >= reminderRepeatMinutes * minute && reminderCount < maximumAutomaticRepeats) {
            reminderCount++;
            sendDeadlineNotification();
            lastNotificationAt = now;
            persist();
        }
    }

    function confirmPosture(newPosture) {
        if (newPosture !== "sitting" && newPosture !== "standing")
            return "ERROR: posture must be sitting or standing";
        if (!remindersEnabled)
            return "ERROR: reminders are disabled";
        if (posture === newPosture)
            return "Already " + newPosture + "; interval unchanged";

        const now = Date.now();
        accountTo(now);
        posture = newPosture;
        postureStartedAt = now;
        pausedMillis = 0;
        dueAt = now + durationFor(posture);
        clearPending();
        graceUntil = 0;
        lastStateUpdateAt = now;
        publish(now);
        persist();
        return "Confirmed " + newPosture;
    }

    function clearPending() {
        closeNotification();
        pendingTarget = "";
        isOverdue = false;
        originalTargetDueAt = 0;
        snoozeUntil = 0;
        lastNotificationAt = 0;
        reminderCount = 0;
    }

    function makeUnknown(now) {
        closeNotification();
        posture = "unknown";
        postureStartedAt = 0;
        dueAt = 0;
        pausedMillis = 0;
        pendingTarget = "";
        isOverdue = false;
        originalTargetDueAt = 0;
        snoozeUntil = 0;
        lastNotificationAt = 0;
        reminderCount = 0;
        lastStateUpdateAt = now;
    }

    function snooze(minutesValue) {
        if (!pendingTarget)
            return "ERROR: no transition is pending";
        const minutes = Number(minutesValue);
        if (!Number.isInteger(minutes) || minutes < 1 || minutes > 60)
            return "ERROR: snooze must be a whole number from 1 to 60";
        const now = Date.now();
        closeNotification();
        snoozeUntil = now + minutes * minute;
        lastNotificationAt = now;
        publish(now);
        persist();
        return "Snoozed for " + minutes + " minutes";
    }

    function dismiss() {
        if (!pendingTarget)
            return "ERROR: no transition is pending";
        closeNotification();
        lastNotificationAt = Date.now();
        publish(lastNotificationAt);
        persist();
        return "Dismissed; transition remains overdue";
    }

    function resetCurrentInterval() {
        if (posture === "unknown")
            return "ERROR: set current posture first";
        const now = Date.now();
        accountTo(now);
        postureStartedAt = now;
        pausedMillis = 0;
        dueAt = now + durationFor(posture);
        clearPending();
        lastStateUpdateAt = now;
        publish(now);
        persist();
        return "Current interval reset";
    }

    function resetToday() {
        const now = Date.now();
        accountTo(now);
        currentDate = SitStandMath.dateKey(now);
        todaySittingSeconds = 0;
        todayStandingSeconds = 0;
        lastStateUpdateAt = now;
        publish(now);
        persist();
        return "Today's statistics reset";
    }

    function resetSession() {
        const now = Date.now();
        accountTo(now);
        makeUnknown(now);
        publish(now);
        persist();
        return "Session reset; set current posture";
    }

    function resetAll() {
        const now = Date.now();
        currentDate = SitStandMath.dateKey(now);
        todaySittingSeconds = 0;
        todayStandingSeconds = 0;
        dailyHistory = [];
        makeUnknown(now);
        pluginService.clearPluginState(pluginId);
        publish(now);
        persist();
        return "All runtime state reset";
    }

    function applyEnabled(value) {
        if (value === remindersEnabled)
            return;
        const now = Date.now();
        accountTo(now);
        if (!value) {
            remindersEnabled = false;
            disabledAt = now;
            closeNotification();
        } else {
            remindersEnabled = true;
            posture = "sitting";
            postureStartedAt = now;
            pausedMillis = 0;
            dueAt = now + durationFor(posture);
            clearPending();
            disabledAt = 0;
            graceUntil = 0;
        }
        lastStateUpdateAt = now;
        publish(now);
        persist();
    }

    function setEnabled(value) {
        applyEnabled(value);
        if (pluginService)
            pluginService.savePluginData(pluginId, "enabled", value);
        return value ? "Reminders enabled; assumed sitting" : "Reminders disabled";
    }

    function recalculateDue() {
        if (!initialized || posture === "unknown")
            return;
        const now = Date.now();
        accountTo(now);
        dueAt = postureStartedAt + durationFor(posture) + pausedMillis;
        if (pendingTarget) {
            clearPending();
            if (now >= dueAt) {
                pendingTarget = opposite(posture);
                isOverdue = true;
                originalTargetDueAt = dueAt;
                sendDeadlineNotification();
                lastNotificationAt = now;
            }
        }
        publish(now);
        persist();
    }

    function sendDeadlineNotification() {
        if (!notifyAvailable)
            return;
        if (SettingsData.soundsEnabled)
            AudioService.playCriticalNotificationSound();
        const action = pendingTarget === "standing" ? "stand" : "sit";
        const actionText = pendingTarget === "standing" ? "I'm standing" : "I'm sitting";
        const title = pendingTarget === "standing" ? "Time to stand" : "Time to sit";
        const body = "Confirm after changing posture or snooze. Closing this notification keeps the transition overdue.";
        if (!actionableNotifications || !notificationActionsSupported) {
            sendPassive(title, body + " Confirm your posture in the Sit/Stand widget.", "normal", true);
            return;
        }
        replaceNotification({
            kind: "deadline",
            command: ["notify-send", "-a", "Sit/Stand Reminder", "-i", "material:desk", "-u", "normal", "-t", "0", "-h", "boolean:suppress-sound:true",
                      "--action=" + action + "=" + actionText,
                      "--action=snooze=Remind me in " + defaultSnoozeMinutes + " min",
                      title, body]
        });
    }

    function sendPassive(title, body, urgency, suppressSound) {
        if (!notifyAvailable)
            return;
        const command = ["notify-send", "-a", "Sit/Stand Reminder", "-i", "material:desk", "-u", urgency, "-t", "0"];
        if (suppressSound)
            command.push("-h", "boolean:suppress-sound:true");
        command.push(title, body);
        Quickshell.execDetached(command);
    }

    function replaceNotification(specification) {
        notificationGeneration++;
        specification.token = notificationGeneration;
        queuedNotification = specification;
        if (notificationProcess && notificationProcess.running)
            notificationProcess.signal(15);
        else
            startQueuedNotification();
    }

    function startQueuedNotification() {
        if (!queuedNotification)
            return;
        const specification = queuedNotification;
        queuedNotification = null;
        notificationProcess = notificationProcessComponent.createObject(root, {
            processToken: specification.token,
            notificationKind: specification.kind,
            command: specification.command
        });
        notificationProcess.running = true;
    }

    function closeNotification() {
        notificationGeneration++;
        queuedNotification = null;
        if (notificationProcess) {
            if (notificationProcess.running)
                notificationProcess.signal(15);
            else {
                notificationProcess.destroy();
                notificationProcess = null;
            }
        }
    }

    function notificationExited(process, output) {
        if (process !== notificationProcess) {
            process.destroy();
            return;
        }
        const valid = process.processToken === notificationGeneration;
        const kind = process.notificationKind;
        notificationProcess = null;
        process.destroy();
        if (queuedNotification)
            startQueuedNotification();
        if (!valid || kind !== "deadline")
            return;
        if (output === "stand")
            confirmPosture("standing");
        else if (output === "sit")
            confirmPosture("sitting");
        else if (output === "snooze")
            snooze(defaultSnoozeMinutes);
        else
            dismiss();
    }

    function statusText(now) {
        if (!remindersEnabled)
            return "Disabled";
        if (posture === "unknown")
            return "Set current posture";
        if (isIdle)
            return "Paused while away";
        if (now < graceUntil)
            return "Resuming in " + Math.ceil((graceUntil - now) / 1000) + "s";
        if (pendingTarget) {
            if (snoozeUntil > now)
                return "Snoozed " + Math.ceil((snoozeUntil - now) / minute) + "m";
            return (pendingTarget === "standing" ? "Stand" : "Sit") + " overdue";
        }
        return (posture === "sitting" ? "Sitting" : "Standing") + " · " + Math.max(0, Math.ceil((dueAt - now) / minute)) + "m";
    }

    function setGlobal(globalValue, value) {
        if (globalValue.value !== value)
            globalValue.set(value);
    }

    function publish(now) {
        const activePause = isIdle ? Math.max(0, now - idleStartedAt) : (!remindersEnabled && disabledAt ? Math.max(0, now - disabledAt) : 0);
        const elapsed = postureStartedAt > 0 ? Math.max(0, Math.floor((now - postureStartedAt - pausedMillis - activePause) / 1000)) : 0;
        setGlobal(globalEnabled, remindersEnabled);
        setGlobal(globalPosture, posture);
        setGlobal(globalPostureStartedAt, postureStartedAt);
        setGlobal(globalDueAt, dueAt);
        setGlobal(globalRemainingSeconds, dueAt > 0 ? Math.ceil((dueAt - now) / 1000) : 0);
        setGlobal(globalPostureElapsedSeconds, elapsed);
        setGlobal(globalPendingTarget, pendingTarget);
        setGlobal(globalIsOverdue, isOverdue);
        setGlobal(globalSnoozeUntil, snoozeUntil);
        setGlobal(globalIsIdle, isIdle);
        setGlobal(globalIsInReturnGrace, now < graceUntil);
        setGlobal(globalReminderCount, reminderCount);
        setGlobal(globalTodaySittingSeconds, Math.floor(todaySittingSeconds));
        setGlobal(globalTodayStandingSeconds, Math.floor(todayStandingSeconds));
        setGlobal(globalDailyHistoryJson, JSON.stringify(dailyHistory));
        setGlobal(globalDailyStandingTargetSeconds, dailyStandingTargetMinutes * 60);
        setGlobal(globalStatusText, statusText(now));
        setGlobal(globalNotificationActionsSupported, notifyAvailable && notificationActionsSupported && actionableNotifications);
    }

    onPluginServiceChanged: tryInitialize()
    onPluginIdChanged: tryInitialize()
    onConfiguredEnabledChanged: {
        if (initialized)
            applyEnabled(configuredEnabled);
    }
    onSittingMinutesChanged: {
        if (initialized && appliedSittingMinutes !== sittingMinutes) {
            appliedSittingMinutes = sittingMinutes;
            if (posture === "sitting")
                recalculateDue();
            else
                persist();
        }
    }
    onStandingMinutesChanged: {
        if (initialized && appliedStandingMinutes !== standingMinutes) {
            appliedStandingMinutes = standingMinutes;
            if (posture === "standing")
                recalculateDue();
            else
                persist();
        }
    }
    IdleMonitor {
        id: awayMonitor
        timeout: root.idleThresholdSeconds
        respectInhibitors: true
        enabled: root.initialized && root.remindersEnabled && root.pauseWhileIdle
        onIsIdleChanged: root.handleIdleChanged(isIdle)
    }

    Process {
        id: notificationSupportProbe
        command: ["notify-send", "--help"]
        running: true
        stdout: StdioCollector { id: notificationSupportOutput }
        onExited: exitCode => {
            root.notifyAvailable = exitCode === 0;
            root.notificationActionsSupported = root.notifyAvailable && notificationSupportOutput.text.indexOf("--action") !== -1;
            if (root.initialized)
                root.publish(Date.now());
        }
    }

    Component {
        id: notificationProcessComponent
        Process {
            id: actionProcess
            property int processToken: 0
            property string notificationKind: ""
            stdout: StdioCollector { id: selectedAction }
            onExited: exitCode => root.notificationExited(actionProcess, selectedAction.text.trim())
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.initialized
        onTriggered: {
            const now = Date.now();
            root.handleClockGap(now);
            root.lastTickAt = now;
            root.evaluate(now);
            root.publish(now);
        }
    }

    Timer {
        interval: 60000
        repeat: true
        running: root.initialized
        onTriggered: {
            const now = Date.now();
            root.accountTo(now);
            root.periodicSaveTicks++;
            if (root.periodicSaveTicks >= 5) {
                root.periodicSaveTicks = 0;
                root.persist();
            }
            root.publish(now);
        }
    }

    IpcHandler {
        target: "sitStandReminder"

        function status(): string { return root.statusText(Date.now()); }
        function history(): string {
            const now = Date.now();
            root.accountTo(now);
            root.publish(now);
            root.persist();
            return JSON.stringify(root.dailyHistory);
        }
        function enable(): string { return root.setEnabled(true); }
        function disable(): string { return root.setEnabled(false); }
        function toggle(): string { return root.setEnabled(!root.remindersEnabled); }
        function sit(): string { return root.confirmPosture("sitting"); }
        function stand(): string { return root.confirmPosture("standing"); }
        function snooze(minutes: string): string { return root.snooze(minutes); }
        function dismiss(): string { return root.dismiss(); }
        function reset(): string { return root.resetCurrentInterval(); }
        function remindNow(): string {
            if (!root.remindersEnabled || root.posture === "unknown")
                return "ERROR: enable reminders and set posture first";
            root.dueAt = Date.now();
            root.evaluate(root.dueAt);
            root.publish(root.dueAt);
            return "Reminder requested";
        }
        function resetSession(): string { return root.resetSession(); }
        function resetToday(): string { return root.resetToday(); }
        function resetAll(): string { return root.resetAll(); }
    }

    PluginGlobalVar { id: globalEnabled; varName: "enabled"; defaultValue: true }
    PluginGlobalVar { id: globalPosture; varName: "posture"; defaultValue: "unknown" }
    PluginGlobalVar { id: globalPostureStartedAt; varName: "postureStartedAt"; defaultValue: 0 }
    PluginGlobalVar { id: globalDueAt; varName: "dueAt"; defaultValue: 0 }
    PluginGlobalVar { id: globalRemainingSeconds; varName: "remainingSeconds"; defaultValue: 0 }
    PluginGlobalVar { id: globalPostureElapsedSeconds; varName: "postureElapsedSeconds"; defaultValue: 0 }
    PluginGlobalVar { id: globalPendingTarget; varName: "pendingTarget"; defaultValue: "" }
    PluginGlobalVar { id: globalIsOverdue; varName: "isOverdue"; defaultValue: false }
    PluginGlobalVar { id: globalSnoozeUntil; varName: "snoozeUntil"; defaultValue: 0 }
    PluginGlobalVar { id: globalIsIdle; varName: "isIdle"; defaultValue: false }
    PluginGlobalVar { id: globalIsInReturnGrace; varName: "isInReturnGrace"; defaultValue: false }
    PluginGlobalVar { id: globalReminderCount; varName: "reminderCount"; defaultValue: 0 }
    PluginGlobalVar { id: globalTodaySittingSeconds; varName: "todaySittingSeconds"; defaultValue: 0 }
    PluginGlobalVar { id: globalTodayStandingSeconds; varName: "todayStandingSeconds"; defaultValue: 0 }
    PluginGlobalVar { id: globalDailyHistoryJson; varName: "dailyHistoryJson"; defaultValue: "[]" }
    PluginGlobalVar { id: globalDailyStandingTargetSeconds; varName: "dailyStandingTargetSeconds"; defaultValue: 7200 }
    PluginGlobalVar { id: globalStatusText; varName: "statusText"; defaultValue: "Loading" }
    PluginGlobalVar { id: globalNotificationActionsSupported; varName: "notificationActionsSupported"; defaultValue: false }

    Component.onDestruction: {
        if (initialized) {
            accountTo(Date.now());
            persist();
        }
        closeNotification();
    }
}
