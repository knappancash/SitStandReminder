# Sit/Stand Reminder

A lightweight DankMaterialShell plugin that reminds you to alternate between sitting and standing. It tracks only the posture changes you confirm—keyboard and mouse activity are never treated as posture detection.

The canonical repository is hosted on [Codeberg](https://codeberg.org/knappancash/SitStandReminder). The [GitHub repository](https://github.com/knappancash/SitStandReminder) is a mirror.

![Sit/Stand Reminder popout](sit-stand-reminder-preview.png)

## Features

- Configurable sitting and standing intervals
- Persistent actionable notifications with one configurable snooze option
- A distinct transition sound using DMS sound settings
- Idle-aware timer pausing
- 30 days of confirmed sitting and standing totals
- Shared state across every bar and monitor

## Installation

Install and enable **Sit/Stand Reminder** from the DMS Plugins page, then add its widget to DankBar or the Control Center.

For local development, link this checkout and rescan plugins:

```sh
mkdir -p ~/.config/DankMaterialShell/plugins
ln -s "$PWD/SitStandReminder" ~/.config/DankMaterialShell/plugins/sitStandReminder
dms ipc call plugin-scan scan
```

Requires DMS 1.5 or newer and `notify-send` from `libnotify`.

## How to use it

1. Open the widget and confirm whether you are sitting or standing.
2. When a transition notification appears, change posture and confirm it from the notification or widget.
3. The notification stays visible until you confirm, snooze, or close it. Closing it leaves the transition overdue.
4. Pause reminders when you do not want them. Enabling them again starts a fresh sitting interval.

The defaults are 30 minutes sitting, 15 minutes standing, and a 10-minute snooze. They are starting points rather than medical guidance; adjust them to what feels comfortable.

## Settings

The plugin settings let you change:

- Sitting, standing, and snooze durations
- Notification repeats and return grace period
- Idle detection and whether idle time counts toward today's totals
- The daily standing target
- Session, daily-statistics, and full-state resets

## Optional IPC

These commands are useful for compositor keybindings:

```sh
dms ipc call sitStandReminder toggle
dms ipc call sitStandReminder sit
dms ipc call sitStandReminder stand
dms ipc call sitStandReminder snooze 10
dms ipc call sitStandReminder reset
dms ipc call sitStandReminder status
dms ipc call sitStandReminder history
```

The popout shows today plus the five most recent completed days. `history` returns all retained completed days as JSON. Only daily totals are stored; there is no event or activity log.

Physical posture always requires explicit confirmation. Notification actions require support from the active notification server; the widget controls continue to work without them.
