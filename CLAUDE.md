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
│   └── plugin.json     # Plugin manifest (metadata + commands only)
├── hooks/
│   └── hooks.json      # Auto-discovered from plugin root
├── sounds/             # Audio files (.aiff)
├── commands/           # Slash command documentation (.md)
└── scripts/
    └── ccbell.sh       # Auto-downloads binary from GitHub releases
```

**:rotating_light: Critical Plugin Structure Rules (from official claude-code repo):rotating_light:**

- `plugin.json` must be in `.claude-plugin/` folder at plugin root
- **Do NOT** add `hooks` field to `plugin.json` - hooks are **auto-discovered** from `hooks/hooks.json`
- Commands are **auto-discovered** from `commands/` directory
- See [security-guidance](https://github.com/anthropics/claude-code/tree/main/plugins/security-guidance) as reference plugin

## :rotating_light: CRITICAL: ALWAYS Validate Against Official Documentation :rotating_light:

**:warning: ALWAYS use BOTH `context7` MCP tool AND the official documentation links below to query official Claude Code documentation before validating or modifying any plugin code. NEVER skip either step. :warning:**

**:no_entry: NEVER assume existing code is correct. Plugin schemas, hook events, manifest formats, and command specifications change between Claude Code versions. Always verify against the latest official documentation using BOTH methods. :no_entry:**

### :gear: Mandatory Validation Steps (ALWAYS DO BOTH)

1. **Resolve library ID with context7:**
   ```
   mcp__context7__resolve-library-id with libraryName="claude-code" and query="Claude Code plugins hooks manifest"
   ```

2. **Query official documentation with context7:**
   ```
   mcp__context7__query-docs with libraryId from step 1 and query="plugin manifest schema hooks commands specification"
   ```

3. **Read official documentation from the provided links:**
   - Read the Plugins Reference sections listed below
   - Read the Hooks Reference sections listed below

4. **Validate structure before making changes:**
   - :mag: Verify `plugin.json` format matches official spec
   - :hook: Confirm hook structure (array vs object format)
   - :memo: Validate command specification format
   - :stopwatch: Check timeout and matcher syntax

### :bookmark: Required Queries for Plugin Validation

When validating plugin code, ALWAYS use BOTH methods:

**With context7 MCP tool, query these topics:**
- :mag_right: "plugin manifest schema JSON structure commands hooks specification"
- :mag_right: "hooks.json hook event matcher type command timeout configuration"
- :mag_right: "plugin.json hooks array format with event field inline hooks specification schema"
- :mag_right: "command specification format name description slash command"

**Additionally, read these official documentation sections:**
- :book: Plugin Manifest section
- :keyboard: Commands section
- :hook: Hooks in Plugins section
- :card_file_box: Manifest Schema section
- :speech_balloon: Command Spec section
- :hook: Hook Spec section
- :zap: Events section
- :toolbox: Hook Types section
- :mag: Matcher section
- :stopwatch: Timeout section

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
- :white_check_mark: Verify `plugin.json` is in `.claude-plugin/` folder (not plugin root)
- :white_check_mark: **Do NOT** include `hooks` field in `plugin.json` - hooks auto-discovered
- :white_check_mark: Verify hooks are in `hooks/hooks.json` at plugin root
- :white_check_mark: Confirm hook event names are current (e.g., `Notification`, `Stop`, `SubagentStop`)
- :white_check_mark: Validate hook structure format (wrapper with `description` + `hooks` object)
- :white_check_mark: Validate hook type specifications (command, agent, skill)
- :white_check_mark: Check matcher patterns and syntax are up to date
- :white_check_mark: Confirm timeout defaults and maximum values

## ccbell Plugin :bell:

Distributes audio notifications for:
- :stop_button: `Stop` - Claude finishes responding
- :question: `Notification` (permission_prompt, idle_prompt) - Claude needs permission or is waiting
- :robot: `SubagentStop` - Subagent task completes

