# Feature: Sound Event Smart Home Monitor

Play sounds for smart home device status changes.

## Summary

Monitor smart home devices (HomeKit, Zigbee, Z-Wave), playing sounds for device state changes and automation events.

## Motivation

- Smart device awareness
- Automation feedback
- Security alerts
- Energy monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Smart Home Events

| Event | Description | Example |
|-------|-------------|---------|
| Device On | Device activated | Light turned on |
| Device Off | Device deactivated | Light turned off |
| Motion Detected | Sensor triggered | Motion alert |
| Door Unlocked | Access granted | Smart lock |
| Temperature Alert | Temp out of range | Too hot/cold |

### Configuration

```go
type SmartHomeMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    HubType           string            `json:"hub_type"` // "homekit", "homeassistant", "mqtt"
    HubAddress        string            `json:"hub_address"` // IP or socket
    WatchDevices      []string          `json:"watch_devices"`
    SoundOnStateChange bool             `json:"sound_on_state_change"`
    SoundOnMotion     bool              `json:"sound_on_motion"`
    SoundOnAlert      bool              `json:"sound_on_alert"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 5 default
}

type SmartHomeEvent struct {
    DeviceName  string
    DeviceType  string // "light", "switch", "sensor", "lock"
    State       string // "on", "off", "open", "closed"
    Value       float64
    EventType   string // "state_change", "motion", "alert"
}
```

### Commands

```bash
/ccbell:smarthome status                     # Show smart home status
/ccbell:smarthome add "Living Room Light"    # Add device to watch
/ccbell:smarthome remove "Living Room Light"
/ccbell:smarthome sound on <sound>
/ccbell:smarthome sound motion <sound>
/ccbell:smarthome test                       # Test smart home sounds
```

### Output

```
$ ccbell:smarthome status

=== Sound Event Smart Home Monitor ===

Status: Enabled
Hub: Home Assistant (homeassistant.local:8123)
State Change Sounds: Yes
Motion Sounds: Yes

Watched Devices: 5

[1] Living Room Light
    Type: Light
    State: ON (brightness 80%)
    Sound: bundled:stop

[2] Front Door Lock
    Type: Lock
    State: LOCKED
    Last Activity: 2 hours ago
    Sound: bundled:stop

[3] Motion Sensor
    Type: Sensor
    State: CLEAR
    Last Motion: 5 min ago
    Sound: bundled:stop

[4] Thermostat
    Type: Climate
    State: 72F (heating)
    Sound: bundled:stop

[5] Garage Door
    Type: Door
    State: CLOSED
    Sound: bundled:stop

Recent Events:
  [1] Living Room Light: ON (10 min ago)
       Brightness: 80%
  [2] Motion Sensor: MOTION (15 min ago)
  [3] Front Door Lock: UNLOCKED (1 hour ago)
       By: Owner

Sound Settings:
  State Change: bundled:stop
  Motion: bundled:stop
  Alert: bundled:stop

[Configure] [Add Device] [Test All]
```

---

## Audio Player Compatibility

Smart home monitoring doesn't play sounds directly:
- Monitoring feature using home automation APIs
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Smart Home Monitor

```go
type SmartHomeMonitor struct {
    config        *SmartHomeMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    deviceState   map[string]*DeviceState
}

type DeviceState struct {
    Name        string
    Type        string
    State       string
    Value       float64
    LastChanged time.Time
}
```

```go
func (m *SmartHomeMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.deviceState = make(map[string]*DeviceState)
    go m.monitor()
}

func (m *SmartHomeMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkDevices()
        case <-m.stopCh:
            return
        }
    }
}

func (m *SmartHomeMonitor) checkDevices() {
    switch m.config.HubType {
    case "homeassistant":
        m.checkHomeAssistantDevices()
    case "mqtt":
        m.checkMQTTDevices()
    case "homekit":
        m.checkHomeKitDevices()
    }
}

func (m *SmartHomeMonitor) checkHomeAssistantDevices() {
    // Use Home Assistant API
    url := fmt.Sprintf("http://%s/api/states", m.config.HubAddress)

    client := &http.Client{Timeout: 5 * time.Second}
    req, _ := http.NewRequest("GET", url, nil)

    resp, err := client.Do(req)
    if err != nil {
        return
    }
    defer resp.Body.Close()

    var devices []map[string]interface{}
    if err := json.NewDecoder(resp.Body).Decode(&devices); err != nil {
        return
    }

    for _, dev := range devices {
        entityID := dev["entity_id"].(string)
        state := dev["state"].(string)

        // Check if we should watch this device
        if len(m.config.WatchDevices) > 0 {
            watched := false
            for _, watchName := range m.config.WatchDevices {
                if strings.Contains(entityID, watchName) {
                    watched = true
                    break
                }
            }
            if !watched {
                continue
            }
        }

        m.evaluateDevice(entityID, state)
    }
}

func (m *SmartHomeMonitor) checkMQTTDevices() {
    // Subscribe to MQTT topics and parse messages
    // This would use a library like paho.mqtt.golang
    // Simplified implementation:

    topics := []string{
        "home/+/state",
        "zigbee2mqtt/+/",
        "shellies/+/status",
    }

    for _, topic := range topics {
        m.checkMQTTTopic(topic)
    }
}

func (m *SmartHomeMonitor) checkMQTTTopic(topic string) {
    // Use mosquitto_sub or similar to get messages
    cmd := exec.Command("mosquitto_sub", "-t", topic, "-C", "1", "-W", "2")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    var msg map[string]interface{}
    if err := json.Unmarshal(output, &msg); err != nil {
        return
    }

    // Parse device state from message
    deviceName := topic
    if state, ok := msg["state"].(string); ok {
        m.evaluateDevice(deviceName, state)
    }
}

func (m *SmartHomeMonitor) checkHomeKitDevices() {
    // Use homebridge CLI or HAP-NodeJS
    cmd := exec.Command("homebridge", "-I", "--api")
    // This is a placeholder - real implementation would parse
    // HomeKit accessory data

    // Alternative: Use hk command line tool
    cmd = exec.Command("hk", "list")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    // Parse device list
    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.HasPrefix(line, "Device:") {
            parts := strings.SplitN(line, ":", 2)
            if len(parts) >= 2 {
                deviceName := strings.TrimSpace(parts[1])
                m.evaluateDevice(deviceName, "unknown")
            }
        }
    }
}

func (m *SmartHomeMonitor) evaluateDevice(name string, state string) {
    lastState := m.deviceState[name]

    if lastState == nil {
        m.deviceState[name] = &DeviceState{
            Name:        name,
            State:       state,
            LastChanged: time.Now(),
        }
        return
    }

    if lastState.State != state {
        // State changed
        lastState.State = state
        lastState.LastChanged = time.Now()
        m.onDeviceStateChange(name, state)
    }
}

func (m *SmartHomeMonitor) onDeviceStateChange(name string, state string) {
    if !m.config.SoundOnStateChange {
        return
    }

    deviceType := m.deviceState[name].Type
    if deviceType == "sensor" && (state == "motion" || state == "detected") {
        m.onMotionDetected(name)
        return
    }

    if deviceType == "lock" && state == "unlocked" {
        m.onDoorUnlocked(name)
        return
    }

    sound := m.config.Sounds["state_change"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *SmartHomeMonitor) onMotionDetected(name string) {
    if !m.config.SoundOnMotion {
        return
    }

    sound := m.config.Sounds["motion"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *SmartHomeMonitor) onDoorUnlocked(name string) {
    if !m.config.SoundOnAlert {
        return
    }

    sound := m.config.Sounds["alert"]
    if sound != "" {
        m.player.Play(sound, 0.7)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| Home Assistant API | Service | Free | Home automation |
| mosquitto_sub | Tool | Free | MQTT subscription |
| hk | Tool | Free | HomeKit CLI |

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
| macOS | Supported | Uses homebridge, hk |
| Linux | Supported | Uses Home Assistant, MQTT |
| Windows | Not Supported | ccbell only supports macOS/Linux |
