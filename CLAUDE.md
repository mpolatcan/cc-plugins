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
- `hooks` can be defined inline in `plugin.json` OR in `hooks/hooks.json` (hooks.json preferred for complex plugins)
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
- :white_check_mark: `hooks` can be in `plugin.json` (inline) or `hooks/hooks.json` (preferred for complex plugins)
- :white_check_mark: Verify hooks are in `hooks/hooks.json` at plugin root (if using hooks.json)
- :white_check_mark: Confirm hook event names are current (e.g., `Notification`, `Stop`, `SubagentStop`)
- :white_check_mark: Validate hook structure format (wrapper with `description` + `hooks` object)
- :white_check_mark: Validate hook type specifications (command, agent, skill)
- :white_check_mark: Check matcher patterns and syntax are up to date
- :white_check_mark: Confirm timeout defaults and maximum values

## :bookmark: Version Bumping Process :rocket:

**:warning: CRITICAL: ALWAYS bump version on every change. Never skip.**

This project uses **Semantic Versioning (SemVer)** for plugin releases:
- `MAJOR` - Breaking changes (incompatible API changes)
- `MINOR` - New features (backward-compatible)
- `PATCH` - Bug fixes (backward-compatible)

### :clipboard: Version Sync Rule

**:rotating_light: VERSION MUST BE SYNCED BETWEEN BOTH REPOSITORIES :rotating_light:**

| Repository | File | Field |
|------------|------|-------|
| cc-plugins | `plugins/ccbell/.claude-plugin/plugin.json` | `version` |
| cc-plugins | `plugins/ccbell/scripts/ccbell.sh` | `PLUGIN_VERSION` |
| ccbell | Built binary | `main.version` (via LDFLAGS) |

**When updating either repository, bump BOTH cc-plugins AND ccbell to the same version.**

### :arrows_counterclockwise: Version Bump Type Decision

| Change Type | Version Bump |
|-------------|--------------|
| Bug fixes, patches | `PATCH` (x.y.Z+1) |
| New features (backward-compatible) | `MINOR` (x.Y+1.0) |
| Breaking changes, removals | `MAJOR` (X+1.0.0) |

### :gear: Version Bump Process (cc-plugins)

**Step 1: Get current version**
```bash
cd plugins/ccbell
CURRENT_VERSION=$(grep '"version"' .claude-plugin/plugin.json | sed 's/.*: *"\([^"]*\)".*/\1/')
echo "Current version: $CURRENT_VERSION"
```

**Step 2: Calculate new version**

For **PATCH** release:
```bash
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
PATCH=${PATCH:-0}
PATCH=$((PATCH + 1))
NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
```

For **MINOR** release:
```bash
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
MINOR=${MINOR:-0}
PATCH=0
MINOR=$((MINOR + 1))
NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
```

For **MAJOR** release:
```bash
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
MINOR=0
PATCH=0
MAJOR=$((MAJOR + 1))
NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
```

**Step 3: Update cc-plugins files**
```bash
# Update plugin.json
sed -i '' "s/\"version\": *\"${CURRENT_VERSION}\"/\"version\": \"${NEW_VERSION}\"/" .claude-plugin/plugin.json

# Update ccbell.sh
sed -i '' "s/PLUGIN_VERSION=\"${CURRENT_VERSION}\"/PLUGIN_VERSION=\"${NEW_VERSION}\"/" scripts/ccbell.sh

# Verify
grep -E '(version|PLUGIN_VERSION)' .claude-plugin/plugin.json scripts/ccbell.sh
```

**Step 4: Commit cc-plugins**
```bash
git add .claude-plugin/plugin.json scripts/ccbell.sh
git commit -m "chore(ccbell): bump version to v${NEW_VERSION}"
git push
```

**Step 5: Tag ccbell source repo**
```bash
cd ../../ccbell
git tag v${NEW_VERSION}
git push origin v${NEW_VERSION}
```

### :checklist: Release Checklist

**:rotating_light: MANDATORY - Do not skip any step :rotating_light:**

1. [ ] Determine version bump type (patch/minor/major)
2. [ ] Get current version from `plugins/ccbell/.claude-plugin/plugin.json`
3. [ ] Calculate new version
4. [ ] **ALWAYS bump version** - Never skip, even for "small" changes
5. [ ] Update `plugin.json` and `ccbell.sh` in cc-plugins
6. [ ] Commit and push cc-plugins
7. [ ] Create git tag in ccbell: `git tag v<version>`
8. [ ] Push tag to ccbell: `git push origin v<version>`

**:no_entry_sign: NEVER skip version bumping - even documentation-only changes require a version bump**

## ccbell Plugin :bell:

Distributes audio notifications for:
- :stop_button: `Stop` - Claude finishes responding
- :question: `Notification` (permission_prompt, idle_prompt) - Claude needs permission or is waiting
- :robot: `SubagentStop` - Subagent task completes

### Commands

| Command | Description |
|---------|-------------|
| `/ccbell:configure` | Interactive setup for sounds, events, cooldowns, and quiet hours |
| `/ccbell:test [event]` | Test sounds (all or specific event) |
| `/ccbell:enable` | Enable all notifications |
| `/ccbell:disable` | Disable all notifications |
| `/ccbell:status` | Show current configuration |
| `/ccbell:profile` | Switch between sound profiles |
| `/ccbell:validate` | Run installation diagnostics |
| `/ccbell:help` | Show help and documentation |

### Supported Events

| Event | Hook | Description |
|-------|------|-------------|
| `stop` | `Stop` | Claude finishes responding |
| `permission_prompt` | `Notification` | Claude needs your permission |
| `idle_prompt` | `Notification` | Claude is waiting for input |
| `subagent` | `SubagentStop` | Background agent completes |

