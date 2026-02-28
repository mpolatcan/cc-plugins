---
name: ccbell-nightly:packs
description: Browse, preview, and install sound packs for ccbell-nightly notifications
argument-hint: "[browse|preview|install|use|uninstall|list] [pack_id]"
allowed-tools: ["Read", "Write", "Bash", "WebFetch", "AskUserQuestion"]
---

# Sound Packs for ccbell-nightly

Browse, preview, and install sound packs that bundle sounds for all notification events. Sound packs are distributed via GitHub releases.

## Quick Start

```bash
/ccbell-nightly:packs browse        # Browse available sound packs
/ccbell-nightly:packs preview minimal  # Preview pack sounds before installing
/ccbell-nightly:packs list          # List installed sound packs
/ccbell-nightly:packs install minimal  # Install a sound pack
/ccbell-nightly:packs use minimal      # Apply pack sounds to events (auto-updates config)
```

## Commands

### Browse Available Packs

List all available sound packs from GitHub releases:

```bash
/ccbell-nightly:packs browse
```

This fetches the latest sound packs from the ccbell-soundpacks repository and displays:
- Pack name and description
- Author information
- Version
- Events included in the pack

### Install a Sound Pack

Download and install a sound pack:

```bash
/ccbell-nightly:packs install <pack_id>
```

Example:
```bash
/ccbell-nightly:packs install minimal
/ccbell-nightly:packs install classic
/ccbell-nightly:packs install futuristic
```

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

## Creating Custom Packs

### Using ccbell-sound-generator (Recommended)

Generate AI-powered sound packs via the web app:
1. Visit [ccbell-sound-generator](https://huggingface.co/spaces/mpolatcan/ccbell-sound-generator)
2. Select a theme (Sci-Fi, Retro 8-bit, Nature, Minimal, etc.)
3. Generate sounds for each event
4. Publish directly to GitHub releases

### Manual Creation

1. Create a directory with your WAV sound files
2. Create a `pack.json` file with metadata (only `id`, `name`, `version`, and `events` are required)
3. Create a GitHub release with the pack files

Example pack structure:
```
my-pack/
├── pack.json
├── stop.wav
├── subagent.wav
├── permission_prompt.wav
├── idle_prompt.wav
├── session_start.wav
├── session_end.wav
├── pre_tool_use.wav
├── post_tool_use.wav
├── subagent_start.wav
└── user_prompt_submit.wav
```

Release as `my-pack-v1.0.0` on the [ccbell-sound-packs](https://github.com/mpolatcan/ccbell-sound-packs) repository with `pack.json` and individual WAV files as release assets.

### Local Packs

You can also create a local pack without publishing:
1. Create a directory in `~/.claude/ccbell-nightly/packs/my-pack/`
2. Add `pack.json` and sound files
3. Use with `/ccbell-nightly:packs use my-pack`

## See Also

- `/ccbell-nightly:status` - View current configuration
- `/ccbell-nightly:configure` - Configure individual events
- `/ccbell-nightly:profile` - Switch between profiles
- `/ccbell-nightly:test` - Test notification sounds
