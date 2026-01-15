---
name: ccbell:packs
description: Browse, preview, and install sound packs for ccbell notifications
argument-hint: "[browse|install|use|uninstall|list] [pack_id]"
allowed-tools: ["Read", "Write", "Bash", "WebFetch", "AskUserQuestion"]
---

# Sound Packs for ccbell

Browse, preview, and install sound packs that bundle sounds for all notification events. Sound packs are distributed via GitHub releases.

## Quick Start

```bash
/ccbell:packs browse    # Browse available sound packs
/ccbell:packs list      # List installed sound packs
/ccbell:packs install minimal  # Install a sound pack
/ccbell:packs use minimal      # Apply pack sounds to events
```

## Commands

### Browse Available Packs

List all available sound packs from GitHub releases:

```bash
/ccbell:packs browse
```

This fetches the latest sound packs from the ccbell-soundpacks repository and displays:
- Pack name and description
- Author information
- Version
- Events included in the pack

### Install a Sound Pack

Download and install a sound pack:

```bash
/ccbell:packs install <pack_id>
```

Example:
```bash
/ccbell:packs install minimal
/ccbell:packs install classic
/ccbell:packs install futuristic
```

### Use a Sound Pack

Apply a pack's sounds to your notification events:

```bash
/ccbell:packs use <pack_id>
```

This updates your configuration to use sounds from the specified pack. You can still override individual event sounds in your config.

### List Installed Packs

Show all installed sound packs:

```bash
/ccbell:packs list
```

### Uninstall a Sound Pack

Remove an installed sound pack:

```bash
/ccbell:packs uninstall <pack_id>
```

### Preview a Pack

Preview sounds from a pack before installing:

```bash
/ccbell:packs preview <pack_id>
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
~/.claude/ccbell/packs/<pack_id>/
```

### Multiple Packs

You can have multiple packs installed and switch between them:
```bash
/ccbell:packs install classic
/ccbell:packs install futuristic
/ccbell:packs use classic      # Switch to classic sounds
/ccbell:packs use futuristic   # Switch to futuristic sounds
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
/ccbell:packs browse  # Check available packs
```

### Sound Not Playing

Verify the pack is properly installed:
```bash
/ccbell:packs list  # Check installed packs
```

If issues persist, reinstall the pack:
```bash
/ccbell:packs uninstall <pack_id>
/ccbell:packs install <pack_id>
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

- `/ccbell:status` - View current configuration
- `/ccbell:configure` - Configure individual events
- `/ccbell:profile` - Switch between profiles
- `/ccbell:test` - Test notification sounds
