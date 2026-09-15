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
| [flowpane](https://github.com/mpolatcan/flowpane) | A live graph of a Claude Code workflow run, drawn beside the transcript | Productivity |

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
- Cross-platform support (macOS, Linux)
- Easy configuration via slash commands

### flowpane

Replaces the default Workflow progress list with a live drawing of the run: a
phase-by-phase graph, a stack, or a timeline in the pane beside the transcript.

**Install:**
```
/plugin install flowpane
```

**Features:**
- Every agent as a node, framed in its own state, with its timing, token spend, tool calls and model
- Three layouts — phases across, phases down, or bars against the clock — or one picked to fit the pane
- Press a node for its prompt, its answer and every tool call it made
- Twelve themes, and a settings dialog for the layout and the detail height
- Reads only what a running workflow writes to disk; nothing leaves the machine

Requires the early-access function-hooks API (`CLAUDE_CODE_ENABLE_FUNCTION_HOOKS=1`) and `/tui fullscreen`.

## Contributing

Want to add your plugin to this marketplace? Open a pull request!

## License

MIT
