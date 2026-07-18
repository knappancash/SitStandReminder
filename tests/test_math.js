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
