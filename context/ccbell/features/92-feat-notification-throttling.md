# Feature: Notification throttling

Prevent notification spam with intelligent throttling.

## Summary

Control notification rate with advanced throttling rules.

## Motivation

- Prevent notification spam
- Graceful handling of rapid events
- Priority-based throttling

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Throttling Rules

| Rule | Description | Example |
|------|-------------|---------|
| Max per minute | Limit notifications per minute | max: 3/min |
| Max per hour | Limit notifications per hour | max: 20/hour |
| Burst control | Allow burst, then slow | burst: 5, rate: 1/min |
| Per event | Throttle per event type | stop: 2/min |
| Cooldown | Minimum time between same event | cooldown: 5s |

### Configuration

```go
type ThrottleConfig struct {
    Enabled           bool                   `json:"enabled"`
    DefaultLimit      int                    `json:"default_limit"`      // per minute
    WindowSec         int                    `json:"window_sec"`         // 60
    PerEventLimits    map[string]int         `json:"per_event_limits"`   // event -> per minute
    BurstSize         int                    `json:"burst_size"`         // initial burst allowed
    RecoveryRate      int                    `json:"recovery_rate"`      // tokens per minute
    DropPolicy        string                 `json:"drop_policy"`        // "oldest", "lowest_priority", "newest"
    QuietOnBurst      bool                   `json:"quiet_on_burst"`     // suppress all during burst
}

type ThrottleState struct {
    EventCounts      map[string]int         `json:"event_counts"`
    LastNotification time.Time              `json:"last_notification"`
    TokensAvailable  int                    `json:"tokens_available"`
    InBurstMode      bool                   `json:"in_burst_mode"`
    BurstTokens      int                    `json:"burst_tokens"`
}
```

### Commands

```bash
/ccbell:throttle enable                  # Enable throttling
/ccbell:throttle disable                 # Disable throttling
/ccbell:throttle set 5                   # 5 notifications/minute
/ccbell:throttle set --per-event stop:3 permission_prompt:5
/ccbell:throttle set --burst 10          # Allow 10 burst
/ccbell:throttle status                  # Show throttling status
/ccbell:throttle reset                   # Reset counters
/ccbell:throttle quiet on                # Quiet during burst
```

### Output

```
$ ccbell:throttle status

=== Throttling Status ===

Enabled: Yes
Global limit: 5/minute
Burst: 10 notifications

Per-Event Limits:
  stop: 3/min
  permission_prompt: 5/min
  idle_prompt: 2/min
  subagent: 10/min

Current Window:
  Used: 3/5
  Remaining: 2
  Resets in: 23s

Burst Mode: Active (7/10 used)
Drop Policy: oldest

[Modify] [Reset] [Disable]
```

---

## Audio Player Compatibility

Throttling doesn't play sounds:
- Rate limiting feature
- No player changes required
- Controls when sounds play

---

## Implementation

### Token Bucket Algorithm

```go
type TokenBucket struct {
    capacity      int
    tokens        int
    lastRefill    time.Time
    refillRate    int // tokens per second
}

func (t *TokenBucket) tryConsume() bool {
    t.refill()

    if t.tokens > 0 {
        t.tokens--
        return true
    }
    return false
}

func (t *TokenBucket) refill() {
    now := time.Now()
    elapsed := now.Sub(t.lastRefill).Seconds()

    if elapsed > 0 {
        newTokens := int(elapsed * float64(t.refillRate))
        t.tokens = min(t.capacity, t.tokens+newTokens)
        t.lastRefill = now
    }
}
```

### Throttle Decision

```go
func (t *ThrottleManager) shouldAllow(eventType string) (bool, string) {
    if !t.config.Enabled {
        return true, ""
    }

    // Check per-event limit
    limit := t.config.DefaultLimit
    if eventLimit, ok := t.config.PerEventLimits[eventType]; ok {
        limit = eventLimit
    }

    // Get or create bucket for event
    bucket := t.getOrCreateBucket(eventType, limit)

    if bucket.tryConsume() {
        return true, ""
    }

    // Throttled
    t.stats.Throttled++
    return false, fmt.Sprintf("rate limit exceeded for %s (%d/min)", eventType, limit)
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| None | - | - | Pure Go implementation |

---

## References

### ccbell Implementation Research

- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - State persistence
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Cooldown check

### Research Sources

- [Token bucket algorithm](https://en.wikipedia.org/wiki/Token_bucket)
- [Leaky bucket vs token bucket](https://www.geeksforgeeks.org/difference-between-leaky-bucket-and-token-bucket-algorithms-in-computer-network/)

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
