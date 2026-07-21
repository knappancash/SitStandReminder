function clampNumber(value, fallback, minimum, maximum) {
    const number = Number(value);
    return Number.isFinite(number) ? Math.min(maximum, Math.max(minimum, number)) : fallback;
}

function dateKey(timestamp, dayStartHour) {
    const date = new Date(timestamp);
    date.setHours(date.getHours() - clampNumber(dayStartHour, 0, 0, 12));
    const month = String(date.getMonth() + 1).padStart(2, "0");
    const day = String(date.getDate()).padStart(2, "0");
    return date.getFullYear() + "-" + month + "-" + day;
}

function startOfDay(timestamp, dayStartHour) {
    const date = new Date(timestamp);
    date.setHours(clampNumber(dayStartHour, 0, 0, 12), 0, 0, 0);
    if (date.getTime() > timestamp)
        date.setDate(date.getDate() - 1);
    return date.getTime();
}

function splitAtDayBoundary(start, end, dayStartHour) {
    const boundary = startOfDay(end, dayStartHour);
    return {
        previousSeconds: Math.max(0, boundary - start) / 1000,
        currentSeconds: Math.max(0, end - Math.max(start, boundary)) / 1000
    };
}

function pausableDuration(duration, remindersEnabled, posture) {
    return remindersEnabled && (posture === "sitting" || posture === "standing") ? Math.max(0, Number(duration) || 0) : 0;
}

function elapsedSince(timestamp, now) {
    return timestamp > 0 ? Math.max(0, now - timestamp) : 0;
}

function isStalePause(duration, stalenessHours) {
    return duration > stalenessHours * 60 * 60 * 1000;
}

function reminderRepeatDue(lastNotificationAt, now, repeatMillis, reminderCount, maximumRepeats) {
    return lastNotificationAt <= 0 || (now - lastNotificationAt >= repeatMillis && reminderCount < maximumRepeats);
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

function hasCurrentDayUnknown(savedDate, currentDate, posture) {
    return savedDate === currentDate && posture === "unknown";
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
        const date = new Date(entry.date + "T12:00:00");
        if (!Number.isFinite(date.getTime()) || dateKey(date.getTime()) !== entry.date)
            return;
        days[entry.date] = {
            date: entry.date,
            sittingSeconds: Math.floor(clampNumber(entry.sittingSeconds, 0, 0, Number.MAX_SAFE_INTEGER)),
            standingSeconds: Math.floor(clampNumber(entry.standingSeconds, 0, 0, Number.MAX_SAFE_INTEGER))
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

function takeHistoryDay(history, date) {
    const days = Array.isArray(history) ? history : [];
    const index = days.findIndex(day => day.date === date);
    if (index < 0)
        return { history: days, sittingSeconds: 0, standingSeconds: 0 };
    return {
        history: days.slice(0, index).concat(days.slice(index + 1)),
        sittingSeconds: days[index].sittingSeconds,
        standingSeconds: days[index].standingSeconds
    };
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

if (typeof module !== "undefined")
    module.exports = {
        clampNumber,
        dateKey,
        startOfDay,
        splitAtDayBoundary,
        pausableDuration,
        elapsedSince,
        isStalePause,
        reminderRepeatDue,
        shiftTimestamp,
        shiftClockTimestamp,
        hasCurrentDayPosture,
        hasCurrentDayUnknown,
        standingTargetReached,
        normalizeHistory,
        recordDay,
        takeHistoryDay,
        historyChart,
        dateFormatWithoutYear,
        nearestChartPoint
    };
