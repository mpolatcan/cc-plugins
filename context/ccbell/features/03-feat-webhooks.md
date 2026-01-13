# Feature: Webhooks

HTTP callbacks on events to trigger external services.

## Summary

Send HTTP requests to configured URLs when events trigger. Enable integrations with Slack, IFTTT, Zapier, custom webhooks.

## Technical Feasibility

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
func (c *CCBell) sendWebhook(url string, event string, data map[string]interface{}) error {
    payload := WebhookPayload{
        Event:     event,
        Timestamp: time.Now().UTC(),
        Data:      data,
        CCBell:    c.versionInfo(),
    }

    body, _ := json.Marshal(payload)

    req, _ := http.NewRequest("POST", url, bytes.NewBuffer(body))
    req.Header.Set("Content-Type", "application/json")
    req.Header.Set("User-Agent", "ccbell/"+c.version)

    client := &http.Client{Timeout: 10 * time.Second}
    resp, err := client.Do(req)

    // Retry logic
    for i := 0; i < 3 && err != nil; i++ {
        time.Sleep(time.Duration(i+1) * time.Second)
        resp, err = client.Do(req)
    }

    return err
}
```

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
