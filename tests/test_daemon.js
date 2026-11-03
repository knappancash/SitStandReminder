const assert = require("assert");
const fs = require("fs");
const path = require("path");
const SitStandMath = require("../SitStandMath.js");

// Runs the daemon's top-level QML functions as plain JavaScript against stubbed DMS services.
const source = fs.readFileSync(path.join(__dirname, "..", "SitStandDaemon.qml"), "utf8");
const H = 60 * 60 * 1000;
const M = 60 * 1000;
const now = new Date(2026, 10, 3, 8, 0).getTime();
Date.now = () => now;

function daemon(saved, pluginData = {}) {
    const root = { SitStandMath, pluginData, pluginId: "sitStandReminder", counts: { saves: 0, sends: 0 } };
    root.pluginService = {
        loadPluginState: () => saved,
        savePluginState: () => root.counts.saves++,
        savePluginData() {},
        clearPluginState() {}
    };
    root.NotificationService = { allWrappers: [], dismissNotification() {} };
    root.SettingsData = { soundsEnabled: false };
    root.AudioService = { playCriticalNotificationSound() {} };
    root.Quickshell = { execDetached: () => root.counts.sends++ };
    root.notificationProcessComponent = {
        createObject: () => {
            root.counts.sends++;
            return { running: false, signal() {}, destroy() {} };
        }
    };
    for (const match of source.matchAll(/^    PluginGlobalVar \{ id: (\w+);/gm))
        root[match[1]] = { value: undefined, set(value) { this.value = value; } };
    const properties = [...source.matchAll(/^    (?:readonly )?property \w+ (\w+): (.+)$/gm)];
    const functions = [...source.matchAll(/^    function (\w+)\(([^)]*)\) \{\n([\s\S]*?)^    \}$/gm)];
    properties.forEach(match => root[match[1]] = undefined);
    new Function("root", "with (root) {" + functions.map(match => `root.${match[1]} = function (${match[2]}) {\n${match[3]}};`).join("\n") + "}")(root);
    properties.forEach(match => root[match[1]] = new Function("root", `with (root) { return (${match[2]}); }`)(root));
    root.tryInitialize();
    return root;
}

const today = SitStandMath.dateKey(now);
const yesterday = SitStandMath.dateKey(now - 24 * H);

// A fresh day starts a full interval, whether the shell stopped active or idle.
let root = daemon({ posture: "sitting", currentDate: yesterday, lastStateUpdateAt: now - 10 * H, postureStartedAt: now - 10.5 * H, dueAt: now - 10 * H });
assert.equal(root.dueAt, now + 30 * M);
root = daemon({ posture: "sitting", currentDate: yesterday, lastStateUpdateAt: now - 10 * H, isIdle: true, idleStartedAt: now - 11 * H, postureStartedAt: now - 11.5 * H, dueAt: now - 10 * H });
assert.equal(root.dueAt, now + 30 * M);

// A same-day restart after a long gap still treats the gap as away time.
root = daemon({ posture: "standing", currentDate: today, lastStateUpdateAt: now - H, postureStartedAt: now - H - 5 * M, dueAt: now - H + 10 * M });
assert.equal(root.dueAt, now + 10 * M);
assert(root.graceUntil > now);

// Failed notifications do not rewrite state on every tick.
root = daemon({ posture: "sitting", currentDate: today, lastStateUpdateAt: now, postureStartedAt: now - 40 * M, dueAt: now - 10 * M, pendingTarget: "standing" });
root.counts.saves = 0;
for (let tick = 1; tick <= 10; tick++)
    root.evaluate(now + tick * 1000);
assert.equal(root.counts.saves, 0);

// Duration changes keep a still-overdue transition and its snooze.
root = daemon({ posture: "sitting", currentDate: today, lastStateUpdateAt: now, postureStartedAt: now - 40 * M, dueAt: now - 10 * M, pendingTarget: "standing" });
root.notifyAvailable = true;
root.notificationActionsSupported = true;
root.snoozeUntil = now + 5 * M;
root.counts.sends = 0;
for (const minutes of [29, 28, 27]) {
    root.sittingMinutes = minutes;
    root.recalculateDue();
}
assert.equal(root.counts.sends, 0);
assert.equal(root.pendingTarget, "standing");
assert.equal(root.snoozeUntil, now + 5 * M);
root.sittingMinutes = 120;
root.recalculateDue();
assert.equal(root.pendingTarget, "");

// Suspend time is not posture time, even when idle time counts.
root = daemon({ posture: "sitting", currentDate: today, lastStateUpdateAt: now, postureStartedAt: now - H, dueAt: now + 10 * M }, { countIdleTime: true });
root.isIdle = true;
root.idleStartedAt = root.lastTickAt = root.lastStateUpdateAt = now - 8 * H;
const sittingBefore = root.todaySittingSeconds;
root.handleClockGap(now);
root.accountTo(now);
assert.equal(root.todaySittingSeconds, sittingBefore);

console.log("test_daemon: passed");
