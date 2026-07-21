const assert = require("assert");
const { FuzzedDataProvider } = require("@jazzer.js/core");
const math = require("../SitStandMath.js");

function generatedNumber(data) {
    return data.pickValue([
        data.consumeDouble(),
        data.consumeIntegral(6, true),
        data.consumeString(20),
        null,
        undefined,
        true,
        Number.MAX_VALUE,
        -Number.MAX_VALUE
    ]);
}

function generatedHistory(data) {
    return Array.from({ length: data.consumeIntegralInRange(0, 40) }, () => ({
        date: data.consumeBoolean()
            ? `${String(data.consumeIntegralInRange(0, 9999)).padStart(4, "0")}-${String(data.consumeIntegralInRange(0, 15)).padStart(2, "0")}-${String(data.consumeIntegralInRange(0, 35)).padStart(2, "0")}`
            : data.consumeString(16),
        sittingSeconds: generatedNumber(data),
        standingSeconds: generatedNumber(data)
    }));
}

module.exports.fuzz = function (input) {
    const data = new FuzzedDataProvider(input.subarray(1));
    const history = math.normalizeHistory((input[0] & 1) === 0 ? input.subarray(1).toString() : generatedHistory(data), 30);

    assert(history.length <= 30);
    assert.deepEqual(history.map(day => day.date), [...new Set(history.map(day => day.date))].sort());
    history.forEach(day => {
        assert.equal(math.dateKey(new Date(`${day.date}T12:00:00`).getTime()), day.date);
        assert(Number.isSafeInteger(day.sittingSeconds) && day.sittingSeconds >= 0);
        assert(Number.isSafeInteger(day.standingSeconds) && day.standingSeconds >= 0);
    });
    assert.deepEqual(math.normalizeHistory(JSON.stringify(history), 30), history);

    const chart = math.historyChart(history, data.consumeIntegralInRange(1, 30));
    assert(Number.isFinite(chart.maximum));
    assert(Number.isFinite(chart.sittingAverage));
    assert(Number.isFinite(chart.standingAverage));

    const selectedDate = history.length > 0 && data.consumeBoolean()
        ? history[data.consumeIntegralInRange(0, history.length - 1)].date
        : data.consumeString(16);
    const recorded = math.recordDay(history, selectedDate, generatedNumber(data), generatedNumber(data), 30);
    assert.deepEqual(recorded, math.normalizeHistory(recorded, 30));
    const taken = math.takeHistoryDay(history, selectedDate);
    assert.equal(taken.history.length, history.length - (history.some(day => day.date === selectedDate) ? 1 : 0));

    if (chart.days.length > 0) {
        const index = data.consumeIntegralInRange(0, chart.days.length - 1);
        const width = data.consumeIntegralInRange(1, 1000);
        const height = data.consumeIntegralInRange(9, 1000);
        const x = (index + 0.5) * width / chart.sitting.length;
        const y = height - 4 - chart.sitting[index] / chart.maximum * (height - 8);
        const nearest = math.nearestChartPoint(chart.sitting, chart.standing, chart.maximum, width, height, x, y, 0);
        assert(nearest && nearest.index === index && nearest.series === 0);
    } else {
        assert.equal(math.nearestChartPoint([], [], 1, 100, 100, 0, 0, 10), null);
    }
    assert.equal(typeof math.dateFormatWithoutYear(data.consumeString(30)), "string");

    const timestamp = data.consumeNumberInRange(946684800000, 2051222400000);
    const dayStartHour = data.consumeIntegralInRange(0, 12);
    const start = math.startOfDay(timestamp, dayStartHour);
    const next = new Date(start);
    next.setDate(next.getDate() + 1);
    assert(start <= timestamp && timestamp < next.getTime());
    assert.equal(math.dateKey(timestamp, dayStartHour), math.dateKey(start, dayStartHour));

    const intervalStart = timestamp - data.consumeIntegralInRange(0, 3 * 24 * 60 * 60 * 1000);
    const split = math.splitAtDayBoundary(intervalStart, timestamp, dayStartHour);
    assert(split.previousSeconds >= 0 && split.currentSeconds >= 0);
    assert(Math.abs(split.previousSeconds + split.currentSeconds - (timestamp - intervalStart) / 1000) < 1e-9);

    const duration = data.consumeNumberInRange(-1e9, 1e9);
    const enabled = data.consumeBoolean();
    const posture = data.pickValue(["sitting", "standing", "unknown", data.consumeString(10)]);
    const paused = math.pausableDuration(duration, enabled, posture);
    assert(Number.isFinite(paused) && paused >= 0);
    assert(math.elapsedSince(timestamp, timestamp + duration) >= 0);
    assert.equal(typeof math.isStalePause(duration, data.consumeIntegralInRange(0, 48)), "boolean");
    assert.equal(typeof math.reminderRepeatDue(timestamp, timestamp + duration, Math.abs(duration), data.consumeIntegralInRange(0, 10), data.consumeIntegralInRange(0, 10)), "boolean");
    assert(Number.isFinite(math.shiftTimestamp(timestamp, duration)));
    assert(Number.isFinite(math.shiftClockTimestamp(timestamp, duration)));
    assert.equal(typeof math.hasCurrentDayPosture(selectedDate, math.dateKey(timestamp), math.dateKey(timestamp), posture), "boolean");
    assert.equal(typeof math.hasCurrentDayUnknown(selectedDate, math.dateKey(timestamp), posture), "boolean");
    assert.equal(typeof math.standingTargetReached(generatedNumber(data), generatedNumber(data)), "boolean");
    assert(Math.abs(math.clampNumber(generatedNumber(data), 0, -10, 10)) <= 10);
};
