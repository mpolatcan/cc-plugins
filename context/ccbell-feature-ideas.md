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
| 1 | **Visual Notifications** | macOS Notification Center, terminal bell, or tray icon alongside audio. Show notification title based on event type with custom message. |
| 2 | **Per-Workspace Config** | Different sound profiles per project/repo using `.claude-ccbell.json`. Allows context-aware notifications (e.g., louder for production, subtle for dev). |
| 3 | **Webhooks** | HTTP callbacks on events (trigger Slack, IFTTT, webhooks). Send JSON payload with event details, timestamp, and custom data. |
| 4 | **Sound Packs** | Download additional sound themes from GitHub. Browse and install community-created sound packs via `/ccbell:packs` command. |
| 5 | **Smart Quieting** | AI-aware quiet periods. Integrate with calendar APIs (Google Calendar, Outlook) to auto-silence during meetings. |

## Medium Priority

| # | Feature | Description |
|---|---------|-------------|
| 6 | **Event Filtering** | Only notify on long responses (>N tokens), specific patterns (error keywords), or error conditions. Regex support for advanced matching. |
| 7 | **Volume Gradients** | Fade in/out for less jarring experience. Configurable ramp duration per event (100ms-2000ms). |
| 8 | **Quick Disable** | Temporary pause (15min, 1hr, 4hr) without full disable. Quick toggle via command or keyboard shortcut. |
| 9 | **Weekday/Weekend Schedules** | Different quiet hours for weekends. Override default schedule with weekend-specific time windows. |
| 10 | **Sound Preview** | Hear sound before confirming selection in configure. Preview mode with loop control. |
| 11 | **Notification Dashboard** | History of recent notifications with stats. Show event frequency, last triggered, daily counts. |

## Nice to Have

| # | Feature | Description |
|---|---------|-------------|
| 12 | **TTS Announcements** | Text-to-speech: "Claude finished", "Permission needed". Customizable phrases per event. Lightweight options: [Flite](http://cmuflite.org/) (~2MB, Go bindings via [flite-go](https://github.com/gen2brain/flite-go)), [eSpeak NG](https://github.com/espeak-ng/espeak-ng) (~3MB). For higher quality: [Piper](https://github.com/rhasspy/piper), [Kokoro](https://github.com/hexgrad/Kokoro-82M). |
| 13 | **Sound Randomization** | Play random sound from a set per event. Create sound pools for variety (e.g., 3 different "stop" sounds). |
| 14 | **Export/Import Config** | Share configurations via JSON. Copy profile settings between machines or share with team. |
| 15 | **Notification Stacking** | Queue rapid notifications and play them as a sequence. Prevent audio chaos during burst events. |

---

## Quick Wins (Easy to Implement)

1. **Hook timeout increase** - Allow longer timeouts for slow systems (configurable via `hooks.json` override)
2. **Config validation command** - `ccbell:doctor` for deeper diagnostics (missing files, permission issues)
3. **Event aliases** - Shorter names like `/ccbell test stop` instead of full paths
4. **Dry-run mode** - Test config without playing sounds, just log what would happen
5. **Config migration tool** - Auto-migrate old config format on update

---

## Potential Integration Ideas

- **Claude Code Hook** - Support Extensions new hook types as they're released
- **Shell Completion** - Add shell completion for event names and commands
- **Config Schema Validation** - JSON Schema for config file with helpful error messages

---

*Last updated: 2026-01-14*
