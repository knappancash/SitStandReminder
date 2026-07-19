const fs = require("fs");
const vm = require("vm");
const source = fs.readFileSync(require("path").join(__dirname, "..", "SitStandMath.js"), "utf8").replace(/^\.pragma library\s*/, "");
const math = {};
vm.createContext(math);
vm.runInContext(source, math);

const assert = require("assert");
assert.equal(math.clampNumber("bad", 30, 1, 60), 30);
assert.equal(math.clampNumber(99, 30, 1, 60), 60);
assert.equal(math.dateKey(new Date(2026, 0, 2).getTime()), "2026-01-02");
const split = math.splitAtDayBoundary(new Date(2026, 0, 1, 23, 59).getTime(), new Date(2026, 0, 2, 0, 1).getTime());
assert.deepEqual(JSON.parse(JSON.stringify(split)), { previousSeconds: 60, currentSeconds: 60 });
assert.equal(math.ceilToMinute(899), 900);
assert.equal(math.ceilToMinute(900), 900);
assert.equal(math.ceilToMinute(-1), 0);
assert.equal(math.resumePosture("standing"), "standing");
assert.equal(math.resumePosture("sitting"), "sitting");
assert.equal(math.resumePosture("unknown"), "sitting");
assert.equal(math.postureToggleOperation("sitting"), "stand");
assert.equal(math.postureToggleOperation("standing"), "sit");
assert.equal(math.postureToggleOperation("unknown"), "sit");
assert.equal(math.shouldUndoPostureChange("standing", "standing", 5000, 4999), true);
assert.equal(math.shouldUndoPostureChange("standing", "standing", 5000, 5001), false);
assert.equal(math.shouldUndoPostureChange("standing", "sitting", 5000, 4999), false);
assert.equal(math.shiftTimestamp(1000, 250), 1250);
assert.equal(math.shiftTimestamp(1000, -250), 1000);
assert.equal(math.shiftTimestamp(0, 250), 0);
assert.equal(math.shiftClockTimestamp(1000, -250), 750);
assert.equal(math.shiftClockTimestamp(1000, 250), 1250);
assert.equal(math.shiftClockTimestamp(0, -250), 0);
assert.equal(math.hasCurrentDayPosture("2026-07-19", "", "2026-07-19", "standing"), true);
assert.equal(math.hasCurrentDayPosture("2026-07-18", "2026-07-19", "2026-07-19", "standing"), true);
assert.equal(math.hasCurrentDayPosture("2026-07-18", "2026-07-18", "2026-07-19", "standing"), false);
assert.equal(math.hasCurrentDayPosture("2026-07-19", "", "2026-07-19", "unknown"), false);
assert.equal(math.standingTargetReached(7200, 7200), true);
assert.equal(math.standingTargetReached(7199, 7200), false);

const history = math.recordDay([
    { date: "2026-01-01", sittingSeconds: 100, standingSeconds: 20 },
    { date: "invalid", sittingSeconds: 999, standingSeconds: 999 },
    { date: "2026-01-02", sittingSeconds: -1, standingSeconds: "30" }
], "2026-01-01", 200, 40, 2);
assert.deepEqual(JSON.parse(JSON.stringify(history)), [
    { date: "2026-01-01", sittingSeconds: 200, standingSeconds: 40 },
    { date: "2026-01-02", sittingSeconds: 0, standingSeconds: 30 }
]);
assert.equal(math.normalizeHistory("not json", 30).length, 0);
assert.equal(math.normalizeHistory(JSON.stringify(history), 30).length, 2);
const chart = math.historyChart(history, 5);
assert.deepEqual(JSON.parse(JSON.stringify(chart)), {
    days: history,
    sitting: [200, 0],
    standing: [40, 30],
    maximum: 200,
    sittingAverage: 100,
    standingAverage: 35,
    labels: [
        { index: 0, date: "2026-01-01" },
        { index: 1, date: "2026-01-02" }
    ]
});
assert.deepEqual(JSON.parse(JSON.stringify(math.historyChart(history, 1).days)), [history[1]]);
const thirtyDays = Array.from({ length: 30 }, (_, index) => ({
    date: "2026-01-" + String(index + 1).padStart(2, "0"),
    sittingSeconds: (index + 1) * 100,
    standingSeconds: (index + 1) * 20
}));
const fortnight = math.historyChart(thirtyDays, 14);
assert.equal(math.historyChart(thirtyDays).days.length, 7);
assert.equal(fortnight.days.length, 14);
assert.equal(fortnight.days[0].date, "2026-01-17");
assert.equal(fortnight.sittingAverage, 2350);
assert.equal(fortnight.standingAverage, 470);
assert.deepEqual(JSON.parse(JSON.stringify(fortnight.labels.map(label => label.index))), [0, 3, 7, 10, 13]);
assert.equal(math.nextHistoryRange(7), 14);
assert.equal(math.nextHistoryRange(14), 30);
assert.equal(math.nextHistoryRange(30), 7);
assert.equal(math.dateFormatWithoutYear("dd.MM.yy"), "dd.MM");
assert.equal(math.dateFormatWithoutYear("M/d/yy"), "M/d");
assert.equal(math.dateFormatWithoutYear("yyyy-MM-dd"), "MM-dd");
assert.deepEqual(JSON.parse(JSON.stringify(math.nearestChartPoint(chart.sitting, chart.standing, chart.maximum, 100, 100, 25, 4, 10))), {
    index: 0,
    series: 0,
    distance: 0
});
assert.equal(math.nearestChartPoint(chart.sitting, chart.standing, chart.maximum, 100, 100, 50, 50, 5), null);
