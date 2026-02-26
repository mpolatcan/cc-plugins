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

Sound packs are distributed as GitHub releases containing:
- `pack.json` - Pack metadata and event mapping
- Sound files for each event (`.aiff`, `.wav`, `.mp3`)

Example `pack.json`:
```json
{
  "id": "minimal",
  "name": "Minimal",
  "description": "Subtle notification sounds",
  "author": "ccbell",
  "version": "1.0.0",
  "events": {
    "stop": "stop.aiff",
    "permission_prompt": "permission.aiff",
    "idle_prompt": "idle.aiff",
    "subagent": "subagent.aiff"
  }
}
```

## Sound Path Format

After installing a pack, sounds are referenced as:
```
pack:pack_id:sound_file
```

Example:
```
pack:minimal:stop.aiff
pack:minimal:permission.aiff
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
    "stop": "pack:classic:stop.aiff",
    "permission_prompt": "pack:futuristic:permission.aiff"
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

To create a custom sound pack:

1. Create a directory with your sound files
2. Create a `pack.json` file with metadata
3. Create a GitHub release with the pack files

Example pack structure:
```
my-pack/
├── pack.json
├── stop.aiff
├── permission_prompt.aiff
├── idle_prompt.aiff
└── subagent.aiff
```

Release as `my-pack-v1.0.0` on GitHub with `pack.json` as a release asset.

## See Also

- `/ccbell-nightly:status` - View current configuration
- `/ccbell-nightly:configure` - Configure individual events
- `/ccbell-nightly:profile` - Switch between profiles
- `/ccbell-nightly:test` - Test notification sounds
