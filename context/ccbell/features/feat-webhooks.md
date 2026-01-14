# Feature: Webhooks 🔗

## Table of Contents

- [Summary](#summary)
- [Motivation](#motivation)
- [Benefit](#benefit)
- [Priority & Complexity](#priority--complexity)
- [Technical Feasibility](#technical-feasibility)
- [Implementation](#implementation)
- [Configuration](#configuration)
- [Commands](#commands)
- [Claude Code Plugin Feasibility](#claude-code-plugin-feasibility)
- [References](#references)

## Summary

Send HTTP requests to configured URLs when events trigger. Enable integrations with Slack, IFTTT, Zapier, custom webhooks.

## Motivation

- Team notifications in Slack/Discord
- Trigger automation workflows
- Mobile notifications via push services
- Custom integrations with existing tools

---

## Benefit

- **Team awareness**: Notify entire channels when Claude completes tasks
- **Automation triggers**: Start workflows based on Claude Code events
- **Multi-device notifications**: Get alerts on phone via push services
- **CI/CD integration**: Connect ccbell with existing notification pipelines

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | High |
| **Complexity** | Medium |
| **Category** | Integration |

---

## Technical Feasibility

### Current Architecture Analysis

The current `cmd/ccbell/main.go` is a short-lived process that:
1. Reads config
2. Checks conditions (quiet hours, cooldown)
3. Plays sound
4. Exits

**Key Finding**: Webhooks can be added as an additional step after sound playback. The Go standard library's `net/http` package is sufficient - no external dependencies needed.

### Webhook Payload

```json
{
  "event": "stop",
  "timestamp": "2026-01-14T10:30:00Z",
  "data": {
    "duration_seconds": 3.2,
    "tokens_used": 1500
  },
  "ccbell": {
    "version": "0.2.30",
    "profile": "default"
  }
}
```

### Implementation

```go
func sendWebhook(url string, event string, data map[string]interface{}) error {
    payload := WebhookPayload{
        Event:     event,
        Timestamp: time.Now().UTC(),
        Data:      data,
        CCBell:    versionInfo(),
    }

    body, _ := json.Marshal(payload)

    req, _ := http.NewRequest("POST", url, bytes.NewBuffer(body))
    req.Header.Set("Content-Type", "application/json")
    req.Header.Set("User-Agent", "ccbell/"+version)

    client := &http.Client{Timeout: 10 * time.Second}
    resp, err := client.Do(req)

    // Retry logic (3 retries with exponential backoff)
    for i := 0; i < 3 && err != nil; i++ {
        time.Sleep(time.Duration(i+1) * time.Second)
        resp, err = client.Do(req)
    }

    return err
}
```

### Configuration

```json
{
  "webhooks": [
    {
      "name": "Slack",
      "url": "https://hooks.slack.com/services/xxx/yyy/zzz",
      "events": ["stop", "subagent"],
      "method": "POST",
      "headers": {
        "X-Custom-Header": "value"
      }
    },
    {
      "name": "IFTTT",
      "url": "https://maker.ifttt.com/trigger/ccbell_event/with/key/xxx",
      "events": ["permission_prompt"],
      "method": "POST"
    }
  ]
}
```

---

## Feasibility Research

### Audio Player Compatibility

Webhooks are independent of audio playback. They can be triggered after the sound is played without affecting the user experience.

### External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| `net/http` | Standard library | Free | Go standard library |
| None | - | - | No external services required |

### Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Standard HTTP client works |
| Linux | ✅ Supported | Standard HTTP client works |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |

### External Services (User-Provided)

| Service | Cost | Integration Type |
|---------|------|------------------|
| Slack | Free tier available | Webhook URL (user-provided) |
| IFTTT | Free tier available | Webhook URL (user-provided) |
| Zapier | Free tier available | Webhook URL (user-provided) |
| Custom | Free | Any HTTP endpoint |

---

## Implementation Notes

### Integration Point

In `cmd/ccbell/main.go`, after successful sound playback:

```go
// After player.Play() succeeds
if cfg.Webhooks != nil {
    for _, webhook := range cfg.Webhooks {
        if slices.Contains(webhook.Events, eventType) {
            go sendWebhook(webhook.URL, eventType, map[string]interface{}{
                "config_path": configPath,
            })
        }
    }
}
```

### Error Handling

- Webhook failures should not block the main notification flow
- Use goroutine to avoid blocking
- Log webhook errors but don't fail the hook

### Security Considerations

- Validate webhook URLs (prevent localhost, internal network)
- Support auth headers
- Rate limiting per webhook

---

## Claude Code Plugin Feasibility

| Aspect | Status | Notes |
|--------|--------|-------|
| **Hook Compatibility** | ✅ Compatible | Works with `Stop`, `Notification`, `SubagentStop` events |
| **Shell Execution** | ✅ Compatible | Uses standard shell commands |
| **Timeout Safe** | ✅ Safe | Fast execution, no timeout risk |
| **Dependencies** | ✅ Minimal | Uses built-in system commands |
| **Background Service** | ❌ Not Needed | Runs inline with notification |

### Implementation Notes

- Designed for Claude Code hook execution model
- Uses shell commands compatible with ccbell architecture
- No additional services or daemons required
- Works within 30-second hook timeout

---

## References

### Research Sources

- [Go net/http package](https://pkg.go.dev/net/http)
- [Slack Webhooks](https://api.slack.com/messaging/webhooks)
- [IFTTT Webhooks](https://ifttt.com/maker_webhooks)

### ccbell Implementation Research

- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Integration point for webhook triggering
- [Go http.Client timeout](https://pkg.go.dev/net/http#Client) - For webhook timeout handling

## Configuration

```json
{
  "webhooks": [
    {
      "name": "Slack",
      "url": "https://hooks.slack.com/services/xxx/yyy/zzz",
      "events": ["stop", "subagent"],
      "method": "POST",
      "headers": {
        "X-Custom-Header": "value"
      }
    },
    {
      "name": "IFTTT",
      "url": "https://maker.ifttt.com/trigger/ccbell_event/with/key/xxx",
      "events": ["permission_prompt"],
      "method": "POST"
    }
  ]
}
```

## Commands

```bash
/ccbell:webhooks list
/ccbell:webhooks add "Slack" https://hooks.slack.com/... --events stop,subagent
/ccbell:webhooks test stop
/ccbell:webhooks remove Slack
```

---

## Repository Impact & Implementation

### ccbell Repository Impact

| Component | Impact | Details |
|-----------|--------|---------|
| **Config** | Add | Add `webhooks` array with name, url, events, method, headers |
| **Core Logic** | Add | Add `WebhookManager` with Send() and Test() methods |
| **New File** | Add | `internal/webhook/webhook.go` for HTTP webhook handling |
| **Main Flow** | Modify | Send webhooks after/before playing sound |
| **Commands** | Add | New `webhooks` command (list, add, test, remove) |

### cc-plugins Repository Impact

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary, not plugin |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/webhooks.md** | Add | New command documentation |
| **commands/configure.md** | Update | Reference webhook options |
| **scripts/ccbell.sh** | Version sync | Match ccbell release tag |

### Rough Implementation

**ccbell - internal/webhook/webhook.go:**
```go
type WebhookManager struct {
    client *http.Client
}

type Webhook struct {
    Name    string            `json:"name"`
    URL     string            `json:"url"`
    Events  []string          `json:"events"`
    Method  string            `json:"method"`
    Headers map[string]string `json:"headers,omitempty"`
}

func (w *WebhookManager) Send(webhook Webhook, event string, data map[string]interface{}) error {
    body, _ := json.Marshal(map[string]interface{}{
        "event":     event,
        "timestamp": time.Now().Format(time.RFC3339),
        "data":      data,
    })

    req, _ := http.NewRequest(webhook.Method, webhook.URL, bytes.NewBuffer(body))
    for k, v := range webhook.Headers {
        req.Header.Set(k, v)
    }
    req.Header.Set("Content-Type", "application/json")

    resp, err := w.client.Do(req)
    if err != nil {
        return err
    }
    defer resp.Body.Close()

    if resp.StatusCode >= 400 {
        return fmt.Errorf("webhook failed: %d", resp.StatusCode)
    }
    return nil
}

func (w *WebhookManager) Test(webhook Webhook) error {
    testData := map[string]interface{}{
        "event":     "test",
        "timestamp": time.Now().Format(time.RFC3339),
        "message":   "ccbell webhook test",
    }
    return w.Send(webhook, "test", testData)
}
```

**ccbell - cmd/ccbell/main.go:**
```go
func main() {
    cfg := config.Load(homeDir)

    eventType := os.Args[1]

    // Send webhooks
    for _, webhook := range cfg.Webhooks {
        for _, e := range webhook.Events {
            if e == eventType {
                go func(w Webhook) {
                    if err := webhookManager.Send(w, eventType, nil); err != nil {
                        log.Error("Webhook %s failed: %v", w.Name, err)
                    }
                }(webhook)
            }
        }
    }

    // Play sound
    // ...
}
```

---

## cc-plugins Repository Impact

| Aspect | Impact | Details |
|--------|--------|---------|
| **Plugin Manifest** | No changes | Feature implemented in ccbell binary, no plugin.json changes |
| **Hooks** | No changes | Works within existing hook events (`Stop`, `Notification`, `SubagentStop`) |
| **Commands** | New documentation | Create `commands/webhooks.md` for webhook management |
| **Sounds** | No changes | No sound file changes needed |

### Technical Details

- **ccbell Version Required**: 0.3.0+
- **Config Schema Change**: Adds `webhooks` array to config (see Configuration section)
- **Files Modified in cc-plugins**:
  - `plugins/ccbell/commands/webhooks.md` (new file with list, add, test, remove commands)
  - `plugins/ccbell/commands/configure.md` (update to reference webhook options)
- **Version Sync Required**: `scripts/ccbell.sh` VERSION must match ccbell release tag

### Implementation Checklist

- [ ] Create `commands/webhooks.md` with webhook management commands
- [ ] Update `commands/configure.md` with webhook configuration options
- [ ] Document Slack/Discord/IFTTT integration examples
- [ ] When ccbell v0.3.0+ releases, sync version to cc-plugins

---

[Back to Feature Index](index.md)
