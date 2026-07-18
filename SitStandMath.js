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
