# Feature: Sound Event Gamepad Monitor

Play sounds for game controller and input events.

## Summary

Monitor game controller connections, button presses, and joystick events, playing sounds for gamepad events.

## Motivation

- Controller connection feedback
- Button press confirmation
- Joystick calibration alerts
- Gaming session awareness

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Gamepad Events

| Event | Description | Example |
|-------|-------------|---------|
| Controller Connected | Gamepad plugged in | USB controller |
| Controller Disconnected | Gamepad unplugged | Disconnected |
| Button Press | Button pressed | A button pressed |
| Trigger Press | Trigger pressed | L2/R2 pressed |
| Low Battery | Controller battery low | < 20% battery |

### Configuration

```go
type GamepadMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    SoundOnConnect   bool              `json:"sound_on_connect"`
    SoundOnDisconnect bool             `json:"sound_on_disconnect"`
    SoundOnButton    bool              `json:"sound_on_button"`
    ButtonsToWatch   []string          `json:"buttons_to_watch"` // "A", "B", "X", "Y"
    BatteryThreshold float64           `json:"battery_threshold"` // 0.2 default
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_ms"` // 50 default
}

type GamepadEvent struct
    Controller string
    EventType  string // "connected", "disconnected", "button_press", "trigger_press"
    Button     string
    Battery    float64
}
```

### Commands

```bash
/ccbell:gamepad status            # Show gamepad status
/ccbell:gamepad connect on        # Enable connect sounds
/ccbell:gamepad add A             # Add button to watch
/ccbell:gamepad sound connect <sound>
/ccbell:gamepad sound button <sound>
/ccbell:gamepad test              # Test gamepad sounds
```

### Output

```
$ ccbell:gamepad status

=== Sound Event Gamepad Monitor ===

Status: Enabled
Connect Sounds: Yes
Disconnect Sounds: Yes

Connected Controllers: 2

[1] Xbox Wireless Controller
    Battery: 85%
    Connected: Yes
    Last Activity: 5 min ago
    Sound: bundled:stop

[2] PlayStation Controller
    Battery: 15%
    Connected: Yes
    Low Battery!
    Sound: bundled:stop

Watched Buttons: 4
  A, B, X, Y

Recent Events:
  [1] Xbox Controller: Connected (30 min ago)
  [2] PlayStation Controller: Low Battery (1 hour ago)
  [3] Xbox Controller: Button A pressed (2 hours ago)

Sound Settings:
  Connected: bundled:stop
  Disconnected: bundled:stop
  Button: bundled:stop

[Configure] [Add Button] [Test All]
```

---

## Audio Player Compatibility

Gamepad monitoring doesn't play sounds directly:
- Monitoring feature using HID APIs
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Gamepad Monitor

```go
type GamepadMonitor struct {
    config         *GamepadMonitorConfig
    player         *audio.Player
    running        bool
    stopCh         chan struct{}
    controllers    map[string]bool
    buttonStates   map[string]map[string]bool
}

func (m *GamepadMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.controllers = make(map[string]bool)
    m.buttonStates = make(map[string]map[string]bool)
    go m.monitor()
}

func (m *GamepadMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Millisecond)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkGamepads()
        case <-m.stopCh:
            return
        }
    }
}

func (m *GamepadMonitor) checkGamepads() {
    connected := m.getConnectedGamepads()

    for controller, isConnected := range connected {
        wasConnected := m.controllers[controller]
        m.controllers[controller] = isConnected

        if isConnected && !wasConnected {
            m.onControllerConnected(controller)
        } else if !isConnected && wasConnected {
            m.onControllerDisconnected(controller)
        }
    }

    // Check buttons if enabled
    if m.config.SoundOnButton {
        m.checkButtons()
    }
}

func (m *GamepadMonitor) getConnectedGamepads() map[string]bool {
    controllers := make(map[string]bool)

    if runtime.GOOS == "darwin" {
        controllers = m.getMacOSGamepads()
    } else if runtime.GOOS == "linux" {
        controllers = m.getLinuxGamepads()
    }

    return controllers
}

func (m *GamepadMonitor) getMacOSGamepads() map[string]bool {
    controllers := make(map[string]bool)

    // Use system_profiler for HID devices
    cmd := exec.Command("system_profiler", "SPUSBDataType")
    output, err := cmd.Output()
    if err != nil {
        return controllers
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, "Controller") ||
           strings.Contains(line, "Gamepad") ||
           strings.Contains(line, "Joystick") {
            parts := strings.Fields(line)
            if len(parts) > 0 {
                controllers[parts[0]] = true
            }
        }
    }

    return controllers
}

func (m *GamepadMonitor) getLinuxGamepads() map[string]bool {
    controllers := make(map[string]bool)

    // Check /dev/input/js*
    entries, err := os.ReadDir("/dev/input")
    if err != nil {
        return controllers
    }

    for _, entry := range entries {
        if strings.HasPrefix(entry.Name(), "js") {
            controllers[entry.Name()] = true
        }
    }

    return controllers
}

func (m *GamepadMonitor) checkButtons() {
    // Read button states from gamepad
    for controller := range m.controllers {
        buttons := m.getButtonStates(controller)

        for button, isPressed := range buttons {
            lastPressed := false
            if m.buttonStates[controller] != nil {
                lastPressed = m.buttonStates[controller][button]
            }

            m.setButtonState(controller, button, isPressed)

            if isPressed && !lastPressed {
                if m.shouldWatchButton(button) {
                    m.onButtonPressed(controller, button)
                }
            }
        }
    }
}

func (m *GamepadMonitor) getButtonStates(controller string) map[string]bool {
    buttons := make(map[string]bool)

    if runtime.GOOS == "darwin" {
        return m.getMacOSButtonStates(controller, buttons)
    } else if runtime.GOOS == "linux" {
        return m.getLinuxButtonStates(controller, buttons)
    }

    return buttons
}

func (m *GamepadMonitor) getMacOSButtonStates(controller string, buttons map[string]bool) map[string]bool {
    // macOS: Use IOKit or Python with hidapi
    cmd := exec.Command("python3", "-c",
        "import hid; print(hid.enumerate())")
    output, err := cmd.Output()
    if err != nil {
        return buttons
    }

    // Parse hid output
    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.Contains(line, controller) {
            // Simplified - real implementation would parse specific buttons
            buttons["A"] = false
            buttons["B"] = false
            buttons["X"] = false
            buttons["Y"] = false
        }
    }

    return buttons
}

func (m *GamepadMonitor) getLinuxButtonStates(controller string, buttons map[string]bool) map[string]bool {
    // Linux: Read from /dev/input/js*
    jsPath := "/dev/input/" + controller
    data, err := os.ReadFile(jsPath)
    if err != nil {
        return buttons
    }

    // Parse joystick events (simplified)
    // Each event is 8 bytes: time(4), value(2), type(1), number(1)
    if len(data) >= 8 {
        buttons["A"] = false
        buttons["B"] = false
    }

    return buttons
}

func (m *GamepadMonitor) shouldWatchButton(button string) bool {
    if len(m.config.ButtonsToWatch) == 0 {
        return true
    }

    for _, b := range m.config.ButtonsToWatch {
        if b == button {
            return true
        }
    }

    return false
}

func (m *GamepadMonitor) setButtonState(controller, button string, pressed bool) {
    if m.buttonStates[controller] == nil {
        m.buttonStates[controller] = make(map[string]bool)
    }
    m.buttonStates[controller][button] = pressed
}

func (m *GamepadMonitor) onControllerConnected(controller string) {
    if !m.config.SoundOnConnect {
        return
    }

    sound := m.config.Sounds["connected"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *GamepadMonitor) onControllerDisconnected(controller string) {
    if !m.config.SoundOnDisconnect {
        return
    }

    sound := m.config.Sounds["disconnected"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *GamepadMonitor) onButtonPressed(controller, button string) {
    if !m.config.SoundOnButton {
        return
    }

    sound := m.config.Sounds["button"]
    if sound != "" {
        m.player.Play(sound, 0.2)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| system_profiler | System Tool | Free | macOS USB devices |
| /dev/input/js* | Device | Free | Linux joystick devices |
| hidapi | Library | Free | Cross-platform HID |

---

## References

### ccbell Implementation Research

- [Player implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Sound playback
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - State tracking

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | Supported | Uses system_profiler/hidapi |
| Linux | Supported | Uses /dev/input/js* |
| Windows | Not Supported | ccbell only supports macOS/Linux |
