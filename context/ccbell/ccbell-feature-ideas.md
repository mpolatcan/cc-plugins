# ccbell Feature Ideas (Revised)

Audio notification enhancements for Claude Code.

## Claude Code Plugin Constraints

Before evaluating features, understand the constraints:
- **Hook-based triggers**: Only `Stop`, `Notification`, `SubagentStop` events
- **Process execution**: Plugin runs as separate process per hook, limited timeout (~30s)
- **Shell commands only**: Can execute `afplay`, `osascript`, `curl`, etc.
- **No background services**: Cannot run persistent daemons
- **No direct API/GUI access**: Must use shell commands for notifications/webhooks
- **Per-session context**: Config persists, but no cross-session state

---

## Current Features

- **4 events**: stop, permission_prompt, idle_prompt, subagent
- **5 profiles**: default, focus, work, loud, silent
- **Quiet hours** with time window
- **Per-event cooldowns** and volume control
- **8 commands** for configuration and testing

---

## High Priority / High Impact

| # | Feature | Description | Feasibility |
|---|---------|-------------|-------------|
| 1 | **Visual Notifications** | macOS Notification Center (`osascript`), terminal bell (`echo -e '\a'`), or tray icon. Title based on event type. | **✅ FEASIBLE** - Simple shell commands, works with existing sound system |
| 2 | **Per-Workspace Config** | Different profiles per project via `.claude-ccbell.json` in workspace root. Louder for production, subtle for dev. | **✅ FEASIBLE** - Check for config file in CWD, merge with global config |
| 3 | **Smart Quieting** | Time-based schedules (quiet hours already exists) + OS-level DnD check (`defaults read`) | **✅ FEASIBLE** - Check macOS Do Not Disturb via shell, no calendar API needed |
| 4 | **Sound Packs** | Download sound themes from GitHub releases. `/ccbell:packs` to browse. | **✅ FEASIBLE** - Reuse existing download mechanism from `ccbell.sh` |
| 5 | **Quick Disable** | Temporary pause (15min, 1hr, 4hr) without full disable. `/ccbell:pause`. | **✅ FEASIBLE** - Store resume timestamp in config, check on each trigger |

---

## Medium Priority

| # | Feature | Description | Feasibility |
|---|---------|-------------|-------------|
| 6 | **Event Filtering** | Only notify on long responses (>N tokens), regex patterns, or error keywords. | **✅ FEASIBLE** - Read hook context for token count, apply regex filters |
| 7 | **Volume Gradients** | Fade in/out for less jarring experience. Configurable ramp (100ms-2000ms). | **⚠️ REQUIRES TOOL** - `afplay` doesn't support fade; need `sox` or `ffmpeg` dependency |
| 8 | **Weekday/Weekend Schedules** | Different quiet hours for weekends. Override default schedule. | **✅ FEASIBLE** - Simple `date +%u` check in bash, easy to implement |
| 9 | **Sound Preview** | Hear sound before confirming selection in configure. Loop control. | **✅ FEASIBLE** - Use `afplay` with `-t` for duration, `-r` for rate |
| 10 | **Notification Stacking** | Queue rapid notifications, play as sequence. Prevent audio chaos. | **✅ FEASIBLE** - Write queue to temp file, consume in background subshell |
| 11 | **Sound Randomization** | Play random sound from set per event. Create sound pools. | **✅ FEASIBLE** - Simple `shuf` or bash array randomization |

---

## Nice to Have

| # | Feature | Description | Feasibility |
|---|---------|-------------|-------------|
| 12 | **Export/Import Config** | Share configurations via JSON. Copy between machines or share with team. | **✅ FEASIBLE** - Reuse existing config file operations |
| 13 | **TTS Announcements** | Text-to-speech: "Claude finished", "Permission needed". Use `say` (macOS). | **⚠️ LIMITED** - macOS only via `say`, heavy for frequent events |
| 14 | **Webhooks** | HTTP callbacks on events (Slack, IFTTT). JSON payload with event details. | **⚠️ LIMITED** - Possible via `curl`, but hits timeout on slow endpoints |
| 15 | **Notification Dashboard** | History of recent notifications with stats. Daily counts, last triggered. | **⚠️ NO UI** - Can log to file, but no native UI; would need `/ccbell:stats` command |

---

## Quick Wins (Easy to Implement)

| # | Feature | Description | Feasibility |
|---|---------|-------------|-------------|
| 16 | **Hook timeout increase** | Allow longer timeouts for slow systems via `hooks.json` override | **✅ FEASIBLE** - Already configurable in hooks.json |
| 17 | **Config validation command** | `ccbell:doctor` for deeper diagnostics (missing files, permissions) | **✅ FEASIBLE** - Reuse existing validation logic, add more checks |
| 18 | **Event aliases** | Shorter names like `/ccbell test stop` instead of full paths | **✅ FEASIBLE** - Simple alias mapping in command parsing |
| 19 | **Dry-run mode** | Test config without playing sounds, log what would happen | **✅ FEASIBLE** - Add `--dry-run` flag to skip audio play |
| 20 | **Config migration tool** | Auto-migrate old config format on update | **✅ FEASIBLE** - Version check in config, apply migrations |

---

## REMOVED Features (Not Feasible)

| Feature | Reason for Removal |
|---------|-------------------|
| **Calendar Integration** (Smart Quieting with Google/Outlook) | Requires OAuth/API access, too complex, external service dependencies |
| **macOS Notification Center via libnotify** | Requires native GUI binary, not possible via shell-only plugin |
| **Tray Icon Notifications** | Requires GUI app, impossible for CLI plugin |

---

## Priority Matrix

```
HIGH IMPACT + HIGH FEASIBILITY (Implement First):
├── Visual Notifications
├── Per-Workspace Config
├── Smart Quieting (OS DnD only, no calendar)
├── Sound Packs
├── Quick Disable
├── Weekday/Weekend Schedules
└── Sound Randomization

HIGH IMPACT + MEDIUM FEASIBILITY (Plan Carefully):
├── Event Filtering
├── Sound Preview
└── Notification Stacking

LOW PRIORITY (If Time Allows):
├── Export/Import Config
├── TTS Announcements (macOS only)
├── Webhooks (timeout risk)
└── Dashboard (no native UI)

REMOVED (Not Feasible):
├── Calendar Integration
├── Native Notification Center
└── Tray Icons
```

---

## Implementation Recommendations

1. **Start with Quick Wins** - Build momentum with easy features (#16-20)
2. **Focus on core audio** - Make existing features rock-solid before adding new ones
3. **Use shell commands** - Keep dependencies minimal (`afplay`, `osascript`, `curl`, `say`)
4. **Avoid background processes** - Claude Code hooks don't support long-running tasks
5. **Test on slow systems** - Ensure timeout limits are respected

---

*Last updated: 2026-01-14*
*Review criteria: Claude Code plugin feasibility, agentic coding use cases, simplicity*
