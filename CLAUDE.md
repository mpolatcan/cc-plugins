# cc-plugins :package:

Claude Code plugin marketplace - hosts distributable plugins.

**:octocat: GitHub:** [mpolatcan/cc-plugins](https://github.com/mpolatcan/cc-plugins)

## Purpose :rocket:

Contains plugin distributions installed via `/plugin install <plugin_name>`. Currently hosts the `ccbell` plugin.

## :rotating_light: CRITICAL: ALWAYS Use TodoWrite for Task Tracking :rotating_light:

**:warning: For every development task, you MUST create and maintain a todo list using the `TodoWrite` tool. :warning:**

### :white_check_mark: Why Use TodoWrite

- :chart_with_upwards_trend: Tracks progress across complex multi-step tasks
- :memo: Ensures no steps are forgotten
- :eyes: Provides visibility into task completion status
- :axe: Helps break down complex work into manageable steps

### :clipboard: Mandatory Todo Usage

1. **Create todo list at task start:**
   ```
   TodoWrite with todos containing:
   - content: "Task description"
   - status: "pending|in_progress|completed"
   - activeForm: "Current action being performed"
   ```

2. **Update as you work:**
   - Mark `in_progress` when starting a task
   - Mark `completed` when finished
   - Add new todos discovered during work
   - Remove completed todos (or keep as history)

3. **:no_entry_sign: Never have more than one `in_progress` task at a time**

### :page_facing_up: Example Todo Structure

```json
[
  {
    "content": "Validate plugin.json against official schema",
    "status": "in_progress",
    "activeForm": "Validating plugin.json against official schema"
  },
  {
    "content": "Fix hook structure format issues",
    "status": "pending",
    "activeForm": "Fixing hook structure format issues"
  },
  {
    "content": "Update CLAUDE.md with findings",
    "status": "pending",
    "activeForm": "Updating CLAUDE.md with findings"
  }
]
```

## Structure :file_folder:

```
plugins/ccbell/
├── .claude-plugin/
│   └── plugin.json     # Plugin manifest with commands and hooks
├── sounds/             # Audio files (.aiff)
├── commands/           # Slash command documentation (.md)
└── scripts/
    └── ccbell.sh       # Auto-downloads binary from GitHub releases
```

## :rotating_light: CRITICAL: ALWAYS Validate Against Official Documentation :rotating_light:

**:warning: ALWAYS use `context7` MCP tool to query official Claude Code documentation before validating or modifying any plugin code. NEVER skip this step. :warning:**

**:no_entry: NEVER assume existing code is correct. Plugin schemas, hook events, manifest formats, and command specifications change between Claude Code versions. Always verify against the latest official documentation. :no_entry:**

### :gear: Mandatory Validation Steps

1. **Resolve library ID:**
   ```
   mcp__context7__resolve-library-id with libraryName="claude-code" and query="Claude Code plugins hooks manifest"
   ```

2. **Query official documentation:**
   ```
   mcp__context7__query-docs with libraryId from step 1 and query="plugin manifest schema hooks commands specification"
   ```

3. **Validate structure before making changes:**
   - :mag: Verify `plugin.json` format matches official spec
   - :hook: Confirm hook structure (array vs object format)
   - :memo: Validate command specification format
   - :stopwatch: Check timeout and matcher syntax

### :bookmark: Required Queries for Plugin Validation

When validating plugin code, ALWAYS query these topics:
- :mag_right: "plugin manifest schema JSON structure commands hooks specification"
- :mag_right: "hooks.json hook event matcher type command timeout configuration"
- :mag_right: "plugin.json hooks array format with event field inline hooks specification schema"
- :mag_right: "command specification format name description slash command"

### :books: Plugins Documentation (ALWAYS READ - NEVER skip) :books:

**:link: Main Plugins Reference:** https://code.claude.com/docs/en/plugins-reference

**:rotating_light: CRITICAL: You MUST READ the content at these URLs. Do NOT just list them. :rotating_light:**

#### Within Plugins Reference:
| Section | URL |
|---------|-----|
| :clipboard: **Plugin Manifest** | https://code.claude.com/docs/en/plugins-reference#manifest |
| :keyboard: **Commands** | https://code.claude.com/docs/en/plugins-reference#commands |
| :hook: **Hooks in Plugins** | https://code.claude.com/docs/en/plugins-reference#hooks |
| :card_file_box: **Manifest Schema** | https://code.claude.com/docs/en/plugins-reference#manifest-schema |
| :speech_balloon: **Command Spec** | https://code.claude.com/docs/en/plugins-reference#command-spec |
| :hook: **Hook Spec** | https://code.claude.com/docs/en/plugins-reference#hook-spec |
| :package: **Plugins Overview** | https://code.claude.com/docs/en/plugins |
| :mag: **Discover Plugins** | https://code.claude.com/docs/en/discover-plugins |
| :shopping_cart: **Plugin Marketplaces** | https://code.claude.com/docs/en/plugin-marketplaces |

### :hook: Hooks Documentation (ALWAYS READ - NEVER skip) :hook:

**:link: Main Hooks Reference:** https://code.claude.com/docs/en/hooks

**:rotating_light: CRITICAL: You MUST READ the content at these URLs. Do NOT just list them. :rotating_light:**

#### Within Hooks Reference:
| Section | URL |
|---------|-----|
| :zap: **Events** | https://code.claude.com/docs/en/hooks#events |
| :toolbox: **Hook Types** | https://code.claude.com/docs/en/hooks#hook-types |
| :mag: **Matcher** | https://code.claude.com/docs/en/hooks#matcher |
| :stopwatch: **Timeout** | https://code.claude.com/docs/en/hooks#timeout |
| :arrows_counterclockwise: **Input/Output** | https://code.claude.com/docs/en/hooks#inputoutput |

**:clipboard: VALIDATION CHECKLIST (NEVER SKIP):**
- :white_check_mark: Verify hook structure format (array with `event` vs object with event as key)
- :white_check_mark: Confirm hook event names are current (e.g., `Notification` vs separate events)
- :white_check_mark: Validate hook type specifications (command, agent, skill)
- :white_check_mark: Check matcher patterns and syntax are up to date
- :white_check_mark: Confirm timeout defaults and maximum values

## ccbell Plugin :bell:

Distributes audio notifications for:
- :stop_button: `Stop` - Claude finishes responding
- :question: `Notification` (permission_prompt) - Claude needs permission
- :hourglass: `Notification` (idle_prompt) - User waiting for input
- :robot: `SubagentStop` - Subagent task completes
