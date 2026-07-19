.pragma library

function clampNumber(value, fallback, minimum, maximum) {
    const number = Number(value);
    return Number.isFinite(number) ? Math.min(maximum, Math.max(minimum, number)) : fallback;
}

function dateKey(timestamp) {
    const date = new Date(timestamp);
    const month = String(date.getMonth() + 1).padStart(2, "0");
    const day = String(date.getDate()).padStart(2, "0");
    return date.getFullYear() + "-" + month + "-" + day;
}

function startOfDay(timestamp) {
    const date = new Date(timestamp);
    date.setHours(0, 0, 0, 0);
    return date.getTime();
}

function splitAtDayBoundary(start, end) {
    const midnight = startOfDay(end);
    return {
        previousSeconds: Math.max(0, midnight - start) / 1000,
        currentSeconds: Math.max(0, end - Math.max(start, midnight)) / 1000
    };
}

function ceilToMinute(seconds) {
    return Math.ceil(Math.max(0, Number(seconds) || 0) / 60) * 60;
}

function resumePosture(previousPosture) {
    return previousPosture === "standing" ? "standing" : "sitting";
}

function postureToggleOperation(currentPosture) {
    return currentPosture === "sitting" ? "stand" : "sit";
}

function shouldUndoPostureChange(previousPosture, requestedPosture, undoUntil, now) {
    return (previousPosture === "sitting" || previousPosture === "standing") && requestedPosture === previousPosture && now <= undoUntil;
}

function shiftTimestamp(timestamp, duration) {
    return timestamp > 0 ? timestamp + Math.max(0, duration) : timestamp;
}

function shiftClockTimestamp(timestamp, clockDelta) {
    return timestamp > 0 ? timestamp + clockDelta : timestamp;
}

function hasCurrentDayPosture(savedDate, lastUpdateDate, currentDate, posture) {
    return (savedDate === currentDate || lastUpdateDate === currentDate) && (posture === "sitting" || posture === "standing");
}

function standingTargetReached(standingSeconds, targetSeconds) {
    return Number(targetSeconds) > 0 && Number(standingSeconds) >= Number(targetSeconds);
}

function normalizeHistory(value, maximumDays) {
    if (typeof value === "string") {
        try {
            value = JSON.parse(value);
        } catch (error) {
            return [];
        }
    }
    if (!Array.isArray(value))
        return [];
    const days = {};
    value.forEach(entry => {
        if (!entry || !/^\d{4}-\d{2}-\d{2}$/.test(entry.date))
            return;
        const sittingSeconds = Number(entry.sittingSeconds);
        const standingSeconds = Number(entry.standingSeconds);
        days[entry.date] = {
            date: entry.date,
            sittingSeconds: Number.isFinite(sittingSeconds) ? Math.max(0, Math.floor(sittingSeconds)) : 0,
            standingSeconds: Number.isFinite(standingSeconds) ? Math.max(0, Math.floor(standingSeconds)) : 0
        };
    });
    const limit = Math.max(1, Math.floor(Number(maximumDays) || 30));
    return Object.keys(days).sort().slice(-limit).map(date => days[date]);
}

function recordDay(history, date, sittingSeconds, standingSeconds, maximumDays) {
    return normalizeHistory((Array.isArray(history) ? history : []).concat([{
        date: date,
        sittingSeconds: sittingSeconds,
        standingSeconds: standingSeconds
    }]), maximumDays);
}

function historyChart(history, maximumDays) {
    const days = (Array.isArray(history) ? history : []).slice(-Math.max(1, Math.floor(Number(maximumDays) || 7)));
    const chart = { days: days, sitting: [], standing: [], maximum: 1, sittingAverage: 0, standingAverage: 0, labels: [] };
    days.forEach(day => {
        const sitting = Math.max(0, Number(day.sittingSeconds) || 0);
        const standing = Math.max(0, Number(day.standingSeconds) || 0);
        chart.sitting.push(sitting);
        chart.standing.push(standing);
        chart.maximum = Math.max(chart.maximum, sitting, standing);
        chart.sittingAverage += sitting;
        chart.standingAverage += standing;
    });
    if (days.length > 0) {
        chart.sittingAverage = Math.floor(chart.sittingAverage / days.length);
        chart.standingAverage = Math.floor(chart.standingAverage / days.length);
        const labelCount = Math.min(5, days.length);
        for (let index = 0; index < labelCount; index++) {
            const dayIndex = labelCount === 1 ? 0 : Math.round(index * (days.length - 1) / (labelCount - 1));
            chart.labels.push({ index: dayIndex, date: days[dayIndex].date });
        }
    }
    return chart;
}

function nextHistoryRange(range) {
    return range === 7 ? 14 : (range === 14 ? 30 : 7);
}

function dateFormatWithoutYear(format) {
    return String(format).replace(/^[yY]+[^dDM]*/, "").replace(/[^dDM]*[yY]+$/, "");
}

function nearestChartPoint(sitting, standing, maximum, width, height, x, y, radius) {
    let nearest = null;
    const series = [sitting, standing];
    series.forEach((values, seriesIndex) => values.forEach((value, index) => {
        const pointX = (index + 0.5) * width / values.length;
        const pointY = height - 4 - value / Math.max(1, maximum) * (height - 8);
        const distance = Math.hypot(x - pointX, y - pointY);
        if (distance <= radius && (!nearest || distance < nearest.distance))
            nearest = { index: index, series: seriesIndex, distance: distance };
    }));
    return nearest;
}
