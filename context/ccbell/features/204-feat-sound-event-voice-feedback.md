# Feature: Sound Event Voice Feedback

Text-to-speech notifications.

## Summary

Speak custom messages using TTS when events occur.

## Motivation

- Accessibility
- Screen-free notifications
- Rich feedback

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### TTS Types

| Type | Description | Example |
|-------|-------------|---------|
| Say | Default message | "Claude has stopped" |
| Custom | Event-specific | "Build complete" |
| Dynamic | Variable content | "3 files modified" |

### Configuration

```go
type VoiceFeedbackConfig struct {
    Enabled       bool              `json:"enabled"`
    Voice         string            `json:"voice"` // "default", "alex", "samantha"
    Rate          float64           `json:"rate"` // 0.5-2.0, 1.0 normal
    Volume        float64           `json:"volume"` // 0.0-1.0
    Messages      map[string]string `json:"messages"` // event -> message
    FallbackSound string            `json:"fallback_sound"` // Sound if TTS fails
}

type VoiceMessage struct {
    Text    string
    Voice   string
    Rate    float64
    Volume  float64
}
```

### Commands

```bash
/ccbell:voice status                # Show TTS status
/ccbell:voice message stop "Claude has finished"
/ccbell:voice message permission "Waiting for permission"
/ccbell:voice voice default         # Set default voice
/ccbell:voice rate 1.5              # Set speech rate
/ccbell:voice volume 0.8            # Set volume
/ccbell:voice test                  # Test TTS
/ccbell:voice list                  # List available voices
```

### Output

```
$ ccbell:voice status

=== Sound Event Voice Feedback ===

Status: Enabled
Voice: Default (Samantha)
Rate: 1.0
Volume: 0.8

Messages:
  stop: "Claude has finished responding"
  permission_prompt: "Waiting for your permission"
  idle_prompt: "Claude is waiting for input"
  subagent: "Background task completed"

Available Voices:
  [1] Samantha (en-US) - Default
  [2] Alex (en-US)
  [3] Victoria (en-US)
  [4] Daniel (en-GB)

[Configure] [Test] [List Voices]
```

---

## Audio Player Compatibility

Voice feedback uses system TTS:
- macOS: `say` command
- Linux: `espeak`, `festival`, or `espeak-ng`

---

## Implementation

### Voice Feedback Manager

```go
type VoiceFeedbackManager struct {
    config   *VoiceFeedbackConfig
    player   *audio.Player
}

func (m *VoiceFeedbackManager) Speak(eventType string, customMsg string) error {
    message := customMsg
    if message == "" {
        message = m.config.Messages[eventType]
        if message == "" {
            message = m.getDefaultMessage(eventType)
        }
    }

    // Expand variables
    message = m.expandMessage(message, eventType)

    return m.speak(message)
}

func (m *VoiceFeedbackManager) speak(message string) error {
    platform := m.getPlatform()

    switch platform {
    case "darwin":
        return m.speakMacOS(message)
    case "linux":
        return m.speakLinux(message)
    default:
        return fmt.Errorf("TTS not supported on %s", platform)
    }
}

func (m *VoiceFeedbackManager) speakMacOS(message string) error {
    args := []string{}

    // Voice selection
    if m.config.Voice != "" && m.config.Voice != "default" {
        args = append(args, "-v", m.config.Voice)
    }

    // Rate adjustment
    if m.config.Rate != 1.0 {
        args = append(args, "-r", fmt.Sprintf("%.0f", m.config.Rate*100))
    }

    args = append(args, message)

    cmd := exec.Command("say", args...)
    return cmd.Start() // Non-blocking
}

func (m *VoiceFeedbackManager) speakLinux(message string) error {
    // Try espeak-ng first
    voices := []string{"espeak-ng", "espeak", "festival"}

    for _, tts := range voices {
        if _, err := exec.LookPath(tts); err == nil {
            return m.speakWithLinuxTTS(tts, message)
        }
    }

    return fmt.Errorf("no TTS engine found")
}

func (m *VoiceFeedbackManager) speakWithLinuxTTS(tts, message string) error {
    var cmd *exec.Cmd

    switch tts {
    case "espeak-ng", "espeak":
        cmd = exec.Command(tts, "-s", fmt.Sprintf("%.0f", m.config.Rate*100),
            "-a", fmt.Sprintf("%.0f", m.config.Volume*100),
            `"`+message+`"`)

    case "festival":
        cmd = exec.Command("festival", "--tts")
        stdin, _ := cmd.StdinPipe()
        go func() {
            stdin.Write([]byte("(SayText \"" + message + "\")\n"))
            stdin.Close()
        }()
    }

    return cmd.Start() // Non-blocking
}

func (m *VoiceFeedbackManager) expandMessage(message, eventType string) string {
    // Expand variables like ${time}, ${date}
    now := time.Now()

    message = strings.ReplaceAll(message, "${time}", now.Format("3:04 PM"))
    message = strings.ReplaceAll(message, "${date}", now.Format("January 2"))
    message = strings.ReplaceAll(message, "${event}", eventType)

    return message
}

func (m *VoiceFeedbackManager) getDefaultMessage(eventType string) string {
    defaults := map[string]string{
        "stop":              "Claude has finished responding",
        "permission_prompt": "Waiting for your permission",
        "idle_prompt":       "Claude is waiting for input",
        "subagent":          "Background task completed",
    }
    return defaults[eventType]
}

func (m *VoiceFeedbackManager) listVoices() ([]string, error) {
    cmd := exec.Command("say", "-v", "?")
    output, err := cmd.Output()
    if err != nil {
        return nil, err
    }

    var voices []string
    lines := strings.Split(string(output), "\n")
    for _, line := range lines {
        if strings.TrimSpace(line) == "" {
            continue
        }
        // Parse voice line: "Alex        en_US    #"
        parts := strings.Fields(line)
        if len(parts) >= 2 {
            voices = append(voices, parts[0])
        }
    }

    return voices, nil
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| say | System Tool | Free | macOS TTS |
| espeak-ng | APT | Free | Linux TTS |
| festival | APT | Free | Linux TTS |

---

## References

### ccbell Implementation Research

- [Player implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Sound fallback
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Message config

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Uses say command |
| Linux | ✅ Supported | Uses espeak-ng/festival |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
