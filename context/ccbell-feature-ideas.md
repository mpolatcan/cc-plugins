# ccbell Feature Ideas

Audio notification enhancements for Claude Code.

## Current Features

- **4 events**: stop, permission_prompt, idle_prompt, subagent
- **5 profiles**: default, focus, work, loud, silent
- **Quiet hours** with time window
- **Per-event cooldowns** and volume control
- **8 commands** for configuration and testing

---

## High Priority / High Impact

| # | Feature | Description |
|---|---------|-------------|
| 1 | **Visual Notifications** | macOS Notification Center, terminal bell, or tray icon alongside audio |
| 2 | **Per-Workspace Config** | Different sound profiles per project/repo (`.claude-ccbell.json`) |
| 3 | **Webhooks** | HTTP callbacks on events (trigger Slack, IFTTT, etc.) |
| 4 | **Sound Packs** | Download additional sound themes from GitHub |
| 5 | **Smart Quieting** | AI-aware quiet periods (integrate with calendar/meeting detection) |

## Medium Priority

| # | Feature | Description |
|---|---------|-------------|
| 6 | **Event Filtering** | Only notify on long responses, specific patterns, or error conditions |
| 7 | **Volume Gradients** | Fade in/out instead of abrupt playback |
| 8 | **Quick Disable** | Temporary pause (15min, 1hr) without full disable |
| 9 | **Weekday/Weekend Schedules** | Different quiet hours for weekends |
| 10 | **Sound Preview** | Hear sound before confirming selection in configure |
| 11 | **Notification Dashboard** | History of recent notifications with stats |

## Nice to Have

| # | Feature | Description |
|---|---------|-------------|
| 12 | **TTS Announcements** | Text-to-speech: "Claude finished", "Permission needed" |
| 13 | **Sound Randomization** | Play random sound from a set per event |
| 14 | **SSH Audio Server** | Play sounds on remote machine |
| 15 | **Export/Import Config** | Share configurations via JSON |
| 16 | **Sound Recording** | Record custom sounds directly in plugin |
| 17 | **Multi-channel Output** | Route different events to different audio devices |

---

## Quick Wins (Easy to Implement)

1. **Hook timeout increase** - Allow longer timeouts for slow systems
2. **Config validation command** - `ccbell:doctor` for deeper diagnostics
3. **Event aliases** - Shorter names like `ccbell test stop` instead of full paths
4. **Dry-run mode** - Test config without playing sounds

---

*Last updated: 2026-01-14*
