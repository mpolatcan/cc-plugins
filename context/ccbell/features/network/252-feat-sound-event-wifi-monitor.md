# Feature: Sound Event WiFi Monitor

Play sounds for WiFi connection changes and signal strength events.

## Summary

Monitor WiFi connections, signal strength changes, and network transitions, playing sounds for WiFi events.

## Motivation

- Network transition feedback
- Signal strength warnings
- Connection status alerts
- Speed change notifications

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### WiFi Events

| Event | Description | Example |
|-------|-------------|---------|
| Connected | WiFi connected | SSID: HomeNet |
| Disconnected | WiFi lost | No connection |
| Signal Weak | Signal < 50% | -70 dBm |
| Signal Strong | Signal improved | -40 dBm |
| Roam | Network changed | AP handover |
| Speed Changed | Link speed change | 100 Mbps -> 600 Mbps |

### Configuration

```go
type WiFiMonitorConfig struct {
    Enabled          bool              `json:"enabled"`
    SoundOnConnect   bool              `json:"sound_on_connect"`
    SoundOnDisconnect bool             `json:"sound_on_disconnect"`
    SoundOnWeakSignal bool             `json:"sound_on_weak_signal"`
    MinSignalPercent int               `json:"min_signal_percent"` // 30 default
    Sounds           map[string]string `json:"sounds"`
    PollInterval     int               `json:"poll_interval_sec"` // 10 default
}

type WiFiEvent struct {
    SSID          string
    BSSID         string
    SignalPercent int
    LinkSpeed     int
    EventType     string // "connected", "disconnected", "weak_signal", "roam"
}
```

### Commands

```bash
/ccbell:wifi status                # Show wifi status
/ccbell:wifi sound connect <sound>
/ccbell:wifi sound disconnect <sound>
/ccbell:wifi sound weak <sound>
/ccbell:wifi test                  # Test wifi sounds
```

### Output

```
$ ccbell:wifi status

=== Sound Event WiFi Monitor ===

Status: Enabled
Connect Sounds: Yes
Disconnect Sounds: Yes
Weak Signal Threshold: 30%

Current Connection:
  SSID: HomeNet
  Signal: 85% (-45 dBm)
  Link Speed: 600 Mbps
  BSSID: AA:BB:CC:DD:EE:FF

  [===================.] 85%

Status: Connected

Recent Events:
  [1] Connected (5 min ago)
       SSID: HomeNet, Signal: 85%
  [2] Roam (1 hour ago)
       Switched to different AP
  [3] Signal Weak (2 hours ago)
       Signal dropped to 25%

Sound Settings:
  Connect: bundled:stop
  Disconnect: bundled:stop
  Weak Signal: bundled:stop
  Roam: bundled:stop

[Configure] [Set Thresholds] [Test All]
```

---

## Audio Player Compatibility

WiFi monitoring doesn't play sounds directly:
- Monitoring feature using system tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### WiFi Monitor

```go
type WiFiMonitor struct {
    config            *WiFiMonitorConfig
    player            *audio.Player
    running           bool
    stopCh            chan struct{}
    lastSSID          string
    lastSignalPercent int
    lastLinkSpeed     int
}

func (m *WiFiMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    go m.monitor()
}

func (m *WiFiMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkWiFi()
        case <-m.stopCh:
            return
        }
    }
}

func (m *WiFiMonitor) checkWiFi() {
    info, err := m.getWiFiInfo()
    if err != nil {
        // WiFi might be off or not available
        if m.lastSSID != "" {
            m.onDisconnected(m.lastSSID)
            m.lastSSID = ""
        }
        return
    }

    m.evaluateWiFiState(info)
}

func (m *WiFiMonitor) getWiFiInfo() (*WiFiInfo, error) {
    if runtime.GOOS == "darwin" {
        return m.getDarwinWiFiInfo()
    }
    return m.getLinuxWiFiInfo()
}

func (m *WiFiMonitor) getDarwinWiFiInfo() (*WiFiInfo, error) {
    info := &WiFiInfo{}

    // Get WiFi status
    cmd := exec.Command("airport", "-I")
    output, err := cmd.Output()
    if err != nil {
        // Try alternative: networksetup
        return m.getDarwinWiFiInfoAlt()
    }

    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        parts := strings.SplitN(line, ":", 2)
        if len(parts) < 2 {
            continue
        }

        key := strings.TrimSpace(parts[0])
        value := strings.TrimSpace(parts[1])

        switch key {
        case "SSID":
            info.SSID = value
        case "BSSID":
            info.BSSID = value
        case "agrCtlRSSI":
            if rssi, err := strconv.Atoi(value); err == nil {
                info.RSSI = rssi
                info.SignalPercent = m.rssiToPercent(rssi)
            }
        case "lastTxRate":
            if speed, err := strconv.Atoi(value); err == nil {
                info.LinkSpeed = speed
            }
        }
    }

    return info, nil
}

func (m *WiFiMonitor) getDarwinWiFiInfoAlt() (*WiFiInfo, error) {
    info := &WiFiInfo{}

    cmd := exec.Command("networksetup", "-getairportpower", "en0")
    output, err := cmd.Output()
    if err != nil {
        return nil, err
    }

    if !strings.Contains(string(output), "On") {
        return nil, fmt.Errorf("WiFi is off")
    }

    // Get SSID
    cmd = exec.Command("networksetup", "-getairportnetwork", "en0")
    output, err = cmd.Output()
    if err == nil {
        // Format: "Current Wi-Fi Network: SSID"
        parts := strings.SplitN(string(output), ":", 2)
        if len(parts) >= 2 {
            info.SSID = strings.TrimSpace(parts[1])
        }
    }

    return info, nil
}

func (m *WiFiMonitor) getLinuxWiFiInfo() (*WiFiInfo, error) {
    info := &WiFiInfo{}

    // Read WiFi interface status
    interfacePath := "/sys/class/net/wlan0/wireless"
    if _, err := os.Stat(interfacePath); os.IsNotExist(err) {
        return nil, fmt.Errorf("no wireless interface")
    }

    // Use iwconfig if available
    cmd := exec.Command("iwconfig", "wlan0")
    output, err := cmd.Output()
    if err == nil {
        outputStr := string(output)

        // Parse SSID
        re := regexp.MustCompile(`ESSID:"([^"]+)"`)
        match := re.FindStringSubmatch(outputStr)
        if len(match) >= 2 {
            info.SSID = match[1]
        }

        // Parse signal level
        re = regexp.MustCompile(`Signal level=(\d+)/\d+`)
        match = re.FindStringSubmatch(outputStr)
        if len(match) >= 2 {
            if signal, err := strconv.Atoi(match[1]); err == nil {
                info.SignalPercent = signal
            }
        }
    }

    return info, nil
}

func (m *WiFiMonitor) rssiToPercent(rssi int) int {
    // Typical RSSI range: -100 (worst) to -30 (best)
    minRSSI := -100
    maxRSSI := -30

    percent := (rssi - minRSSI) * 100 / (maxRSSI - minRSSI)
    if percent > 100 {
        percent = 100
    }
    if percent < 0 {
        percent = 0
    }

    return percent
}

func (m *WiFiMonitor) evaluateWiFiState(info *WiFiInfo) {
    // Detect connection
    if m.lastSSID == "" && info.SSID != "" {
        m.onConnected(info)
    }

    // Detect disconnection
    if m.lastSSID != "" && info.SSID == "" {
        m.onDisconnected(m.lastSSID)
    }

    // Detect weak signal
    if info.SignalPercent < m.config.MinSignalPercent &&
       m.lastSignalPercent >= m.config.MinSignalPercent {
        m.onWeakSignal(info)
    }

    // Detect roaming
    if m.lastSSID == info.SSID && m.lastBSSID != "" && info.BSSID != "" &&
       m.lastBSSID != info.BSSID {
        m.onRoam(info)
    }

    // Update last state
    m.lastSSID = info.SSID
    m.lastBSSID = info.BSSID
    m.lastSignalPercent = info.SignalPercent
    m.lastLinkSpeed = info.LinkSpeed
}

func (m *WiFiMonitor) onConnected(info *WiFiInfo) {
    if !m.config.SoundOnConnect {
        return
    }

    sound := m.config.Sounds["connected"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *WiFiMonitor) onDisconnected(ssid string) {
    if !m.config.SoundOnDisconnect {
        return
    }

    sound := m.config.Sounds["disconnected"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *WiFiMonitor) onWeakSignal(info *WiFiInfo) {
    if !m.config.SoundOnWeakSignal {
        return
    }

    sound := m.config.Sounds["weak_signal"]
    if sound != "" {
        m.player.Play(sound, 0.6)
    }
}

func (m *WiFiMonitor) onRoam(info *WiFiInfo) {
    sound := m.config.Sounds["roam"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| airport | System Tool | Free | macOS WiFi diagnostics |
| networksetup | System Tool | Free | macOS network config |
| iwconfig | System Tool | Free | Linux wireless tools |
| /sys/class/net | File | Free | Linux network info |

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
| macOS | Supported | Uses airport, networksetup |
| Linux | Supported | Uses iwconfig, /sys |
| Windows | Not Supported | ccbell only supports macOS/Linux |
