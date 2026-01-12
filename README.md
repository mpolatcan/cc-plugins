# cc-plugins

A curated marketplace of plugins for Claude Code.

## Usage

### Add the Marketplace

```
/plugin marketplace add mpolatcan/cc-plugins
```

### Browse Available Plugins

```
/plugin marketplace list
```

### Install a Plugin

```
/plugin install <plugin-name>
```

## Available Plugins

| Plugin | Description | Category |
|--------|-------------|----------|
| [ccbell](./plugins/ccbell) | Audio notifications for Claude Code events | Productivity |

## Plugin Details

### ccbell

Audio notifications for Claude Code events - play sounds when Claude finishes responding, needs permission, is waiting for input, or when a subagent completes.

**Install:**
```
/plugin install ccbell
```

**Features:**
- Play sounds on multiple Claude Code events (stop, permission_prompt, idle_prompt, subagent)
- Support for bundled sounds, custom audio files
- Cross-platform support (macOS, Linux, Windows)
- Easy configuration via slash commands

## Contributing

Want to add your plugin to this marketplace? Open a pull request!

## License

MIT
