# Feature: Webhooks 🔗

## Summary

Send HTTP requests to configured URLs when events trigger. Enable integrations with Slack, IFTTT, Zapier, custom webhooks.

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

## Technical Feasibility

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

### Implementation

```go
type Webhook struct {
    Name    string            `json:"name"`
    URL     string            `json:"url"`
    Events  []string          `json:"events"`
    Method  string            `json:"method"`
    Headers map[string]string `json:"headers,omitempty"`
}

type WebhookPayload struct {
    Event     string                 `json:"event"`
    Timestamp time.Time              `json:"timestamp"`
    Data      map[string]interface{} `json:"data,omitempty"`
    CCBell    map[string]string      `json:"ccbell"`
}

func (w *WebhookManager) Send(webhook Webhook, event string, data map[string]interface{}) error {
    payload := WebhookPayload{
        Event:     event,
        Timestamp: time.Now().UTC(),
        Data:      data,
        CCBell:    versionInfo(),
    }

    body, _ := json.Marshal(payload)
    req, _ := http.NewRequest(webhook.Method, webhook.URL, bytes.NewBuffer(body))
    for k, v := range webhook.Headers {
        req.Header.Set(k, v)
    }
    req.Header.Set("Content-Type", "application/json")

    client := &http.Client{Timeout: 10 * time.Second}
    resp, err := client.Do(req)

    for i := 0; i < 3 && err != nil; i++ {
        time.Sleep(time.Duration(i+1) * time.Second)
        resp, err = client.Do(req)
    }

    return err
}
```

### Commands

```bash
/ccbell:webhooks list                       # List configured webhooks
/ccbell:webhooks add "Slack" <url>          # Add a webhook
/ccbell:webhooks test stop                  # Test webhook for an event
/ccbell:webhooks remove Slack               # Remove a webhook
```

## Repository Impact

### ccbell Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **Config** | Add | Add `webhooks` array with name, url, events, method, headers |
| **Core Logic** | Add | Add `WebhookManager` with Send() and Test() methods |
| **New File** | Add | `internal/webhook/webhook.go` for HTTP webhook handling |
| **Main Flow** | Modify | Send webhooks after/before playing sound |
| **Commands** | Add | New `webhooks` command (list, add, test, remove) |

### cc-plugins Repository

| Component | Impact | Details |
|-----------|--------|---------|
| **plugin.json** | No change | Feature in binary |
| **hooks/hooks.json** | No change | Uses existing hooks |
| **commands/webhooks.md** | Add | New command documentation |
| **commands/configure.md** | Update | Reference webhook options |
| **scripts/ccbell.sh** | Version sync | Match ccbell release tag |

## References

- [Go net/http package](https://pkg.go.dev/net/http)
- [Slack Webhooks](https://api.slack.com/messaging/webhooks)
- [IFTTT Webhooks](https://ifttt.com/maker_webhooks)
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go)

---

[Back to Feature Index](index.md)
