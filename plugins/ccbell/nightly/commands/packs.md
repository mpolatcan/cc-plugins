---
name: ccbell-nightly:packs
description: Browse, preview, and install sound packs for ccbell-nightly notifications
argument-hint: "[browse|preview|install|use|uninstall|list] [pack_id]"
allowed-tools: ["Read", "Write", "Bash", "WebFetch", "AskUserQuestion"]
---

# Sound Packs for ccbell-nightly

Browse, preview, and install sound packs that bundle sounds for all notification events. Install official curated packs from the catalog, or install user-generated packs directly from the [ccbell-sound-generator](https://huggingface.co/spaces/mpolatcan/ccbell-sound-generator) via URL.

## Quick Start

```bash
/ccbell-nightly:packs browse                    # Browse official sound packs
/ccbell-nightly:packs preview minimal           # Preview pack sounds before installing
/ccbell-nightly:packs list                      # List installed sound packs
/ccbell-nightly:packs install minimal           # Install an official pack from catalog
/ccbell-nightly:packs install --url <url>       # Install a user-generated pack from URL
/ccbell-nightly:packs use minimal               # Apply pack sounds to events (auto-updates config)
```

## Commands

### Browse Official Packs

List all available official sound packs:

```bash
/ccbell-nightly:packs browse
```

**How to implement:**

1. Fetch the pack index using WebFetch:
   - URL: `https://raw.githubusercontent.com/mpolatcan/ccbell-sound-packs/main/index.json`
   - This returns a JSON catalog of all official packs

2. Parse the response and display each pack:

```
## Official Sound Packs

| Pack | Description | Version | Events |
|------|-------------|---------|--------|
| minimal | Clean, professional notification sounds | 1.0.0 | stop, subagent, permission_prompt, idle_prompt |
| sci-fi | Futuristic digital notification sounds | 1.0.0 | stop, subagent, permission_prompt, idle_prompt |
| ... | ... | ... | ... |

Install a pack: /ccbell-nightly:packs install <pack_id>
Preview a pack: /ccbell-nightly:packs preview <pack_id>

Generate your own: https://huggingface.co/spaces/mpolatcan/ccbell-sound-generator
```

3. If the fetch fails (network error), inform the user and suggest checking their connection

### Install a Sound Pack

#### From official catalog

Install an official pack by ID:

```bash
/ccbell-nightly:packs install <pack_id>
```

Example:
```bash
/ccbell-nightly:packs install minimal
/ccbell-nightly:packs install classic
/ccbell-nightly:packs install futuristic
```

**How to implement:**

1. Fetch `index.json` from `https://raw.githubusercontent.com/mpolatcan/ccbell-sound-packs/main/index.json`
2. Find the pack entry by `pack_id`, get the `release_tag`
3. Download pack assets from the GitHub release using the release tag
4. Extract to `~/.claude/ccbell-nightly/packs/<pack_id>/`

#### From URL (user-generated packs)

Install a pack from a download URL (e.g., from ccbell-sound-generator):

```bash
/ccbell-nightly:packs install --url <download_url>
```

Example:
```bash
/ccbell-nightly:packs install --url https://huggingface.co/spaces/mpolatcan/ccbell-sound-generator/api/download/my-pack
```

**How to implement:**

1. Download the zip file from the provided URL using Bash (`curl`)
2. Extract the zip to a temporary directory
3. Read `pack.json` from the extracted files to get the `id`
4. Move the extracted files to `~/.claude/ccbell-nightly/packs/<pack_id>/`
5. Confirm installation to the user

### Use a Sound Pack

Apply a pack's sounds to your notification events:

```bash
/ccbell-nightly:packs use <pack_id>
```

This updates your configuration to use sounds from the specified pack. You can still override individual event sounds in your config.

### List Installed Packs

Show all installed sound packs:

```bash
/ccbell-nightly:packs list
```

### Uninstall a Sound Pack

Remove an installed sound pack:

```bash
/ccbell-nightly:packs uninstall <pack_id>
```

### Preview a Pack

Preview sounds from a pack before installing:

```bash
/ccbell-nightly:packs preview <pack_id>
```

## Sound Pack Format

Sound packs are distributed as GitHub releases on [ccbell-sound-packs](https://github.com/mpolatcan/ccbell-sound-packs) containing:
- `pack.json` - Pack manifest with metadata, event mapping, and generation info
- Individual WAV sound files for each event (44.1kHz stereo)

Packs can be generated using the [ccbell-sound-generator](https://huggingface.co/spaces/mpolatcan/ccbell-sound-generator) web app, which uses AI (Stable Audio Open) to create themed notification sounds.

Example `pack.json`:
```json
{
  "id": "minimal",
  "name": "Minimal",
  "description": "Clean, professional notification sounds",
  "author": "ccbell-sound-generator",
  "version": "1.0.0",
  "events": {
    "stop": "stop.wav",
    "subagent": "subagent.wav",
    "permission_prompt": "permission_prompt.wav",
    "idle_prompt": "idle_prompt.wav",
    "session_start": "session_start.wav",
    "session_end": "session_end.wav",
    "pre_tool_use": "pre_tool_use.wav",
    "post_tool_use": "post_tool_use.wav",
    "subagent_start": "subagent_start.wav",
    "user_prompt_submit": "user_prompt_submit.wav"
  },
  "prompts": {
    "stop": "completion chime, minimal, pure melodic tone, subtle, 2.0 seconds, 44.1kHz stereo",
    "subagent": "soft confirmation ding, minimal, clean bell, refined, 1.5 seconds, 44.1kHz stereo"
  },
  "source": {
    "provider": "ccbell-sound-generator",
    "model": "stable-audio-open-small",
    "license": "stabilityai/stable-audio-open-1.0"
  }
}
```

### Supported Events

| Event | Description |
|-------|-------------|
| `stop` | Claude finishes responding |
| `subagent` | Background agent completes |
| `permission_prompt` | Claude needs your permission |
| `idle_prompt` | Claude is waiting for input |
| `session_start` | New Claude Code session started |
| `session_end` | Claude Code session ended |
| `pre_tool_use` | Before a tool call executes |
| `post_tool_use` | After a tool completes |
| `subagent_start` | New subagent spawned |
| `user_prompt_submit` | User submitted a new prompt |

A pack does not need to include sounds for all events. Missing events will fall back to the default bundled sounds.

## Sound Path Format

After installing a pack, sounds are referenced as:
```
pack:pack_id:sound_file
```

Example:
```
pack:minimal:stop.wav
pack:minimal:permission_prompt.wav
```

## Managing Packs

### Installation Location

Installed packs are stored in:
```
~/.claude/ccbell-nightly/packs/<pack_id>/
```

### Multiple Packs

You can have multiple packs installed and switch between them:
```bash
/ccbell-nightly:packs install classic
/ccbell-nightly:packs install futuristic
/ccbell-nightly:packs use classic      # Switch to classic sounds
/ccbell-nightly:packs use futuristic   # Switch to futuristic sounds
```

### Mixing Sounds

You can mix sounds from different packs:
```json
{
  "events": {
    "stop": "pack:classic:stop.wav",
    "permission_prompt": "pack:futuristic:permission_prompt.wav"
  }
}
```

## Troubleshooting

### Pack Not Found

Ensure the pack ID is correct:
```bash
/ccbell-nightly:packs browse  # Check available packs
```

### Sound Not Playing

Verify the pack is properly installed:
```bash
/ccbell-nightly:packs list  # Check installed packs
```

If issues persist, reinstall the pack:
```bash
/ccbell-nightly:packs uninstall <pack_id>
/ccbell-nightly:packs install <pack_id>
```

### Network Issues

If browsing fails, check your internet connection. Packs are fetched from GitHub releases.

## Creating Your Own Packs

### Using ccbell-sound-generator (Recommended)

Generate AI-powered sound packs via the web app and install directly:
1. Visit [ccbell-sound-generator](https://huggingface.co/spaces/mpolatcan/ccbell-sound-generator)
2. Select a theme (Sci-Fi, Retro 8-bit, Nature, Minimal, etc.)
3. Generate sounds for each event
4. Click "Download Pack" - the generator shows an install command
5. Run the command in Claude Code:
   ```bash
   /ccbell-nightly:packs install --url https://huggingface.co/.../api/download/my-pack
   ```

### Manual Local Packs

Create a pack manually without the generator:
1. Create a directory in `~/.claude/ccbell-nightly/packs/my-pack/`
2. Add `pack.json` and WAV sound files
3. Use with `/ccbell-nightly:packs use my-pack`

Minimum `pack.json` (only `id`, `name`, `version`, and `events` are required):
```json
{
  "id": "my-pack",
  "name": "My Pack",
  "version": "1.0.0",
  "events": {
    "stop": "stop.wav",
    "permission_prompt": "permission_prompt.wav"
  }
}
```

## See Also

- `/ccbell-nightly:status` - View current configuration
- `/ccbell-nightly:configure` - Configure individual events
- `/ccbell-nightly:profile` - Switch between profiles
- `/ccbell-nightly:test` - Test notification sounds
