const assert = require("assert");
const math = require("../SitStandMath.js");

const initialSeed = Number(process.env.FUZZ_SEED || 0x51a57a7d) >>> 0;
let seed = initialSeed;
function random() {
    seed = (seed * 1664525 + 1013904223) >>> 0;
    return seed / 0x100000000;
}
function integer(minimum, maximum) {
    return minimum + Math.floor(random() * (maximum - minimum + 1));
}

for (let index = 0; index < 20000; index++) {
    const timestamp = integer(946684800, 2051222400) * 1000 + integer(0, 999);
    const dayStartHour = integer(0, 12);
    const start = math.startOfDay(timestamp, dayStartHour);
    const next = new Date(start);
    next.setDate(next.getDate() + 1);

    assert(start <= timestamp && timestamp < next.getTime());
    assert.equal(math.dateKey(timestamp, dayStartHour), math.dateKey(start, dayStartHour));

    const intervalStart = timestamp - integer(0, 3 * 24 * 60 * 60 * 1000);
    const split = math.splitAtDayBoundary(intervalStart, timestamp, dayStartHour);
    assert(split.previousSeconds >= 0 && split.currentSeconds >= 0);
    assert(Math.abs(split.previousSeconds + split.currentSeconds - (timestamp - intervalStart) / 1000) < 1e-9);
}

const numberValues = [undefined, null, false, true, "", "12.9", "nope", -1, 0, 1.8, Number.MAX_VALUE, Infinity, NaN];
for (let iteration = 0; iteration < 5000; iteration++) {
    const input = Array.from({ length: integer(0, 60) }, () => ({
        date: `${integer(1990, 2050)}-${String(integer(0, 15)).padStart(2, "0")}-${String(integer(0, 35)).padStart(2, "0")}`,
        sittingSeconds: numberValues[integer(0, numberValues.length - 1)],
        standingSeconds: numberValues[integer(0, numberValues.length - 1)]
    }));
    const history = math.normalizeHistory(input, 30);

    assert(history.length <= 30);
    assert.deepEqual(history.map(day => day.date), [...new Set(history.map(day => day.date))].sort());
    history.forEach(day => {
        const parsed = new Date(`${day.date}T12:00:00`);
        assert(!Number.isNaN(parsed.getTime()) && math.dateKey(parsed.getTime()) === day.date, day.date);
        assert(Number.isSafeInteger(day.sittingSeconds) && day.sittingSeconds >= 0);
        assert(Number.isSafeInteger(day.standingSeconds) && day.standingSeconds >= 0);
    });

    const chart = math.historyChart(history, integer(0, 30));
    assert(Number.isFinite(chart.maximum));
    assert(Number.isFinite(chart.sittingAverage));
    assert(Number.isFinite(chart.standingAverage));
}

console.log(`fuzz_math: seed=${initialSeed} passed`);
