# Feature: Sound Rate Limiting

Rate limit sound notifications.

## Summary

Control how frequently sounds can be played within a time window.

## Motivation

- Prevent notification spam
- Limit resource usage
- User-defined limits

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Rate Limit Types

| Type | Description | Example |
|------|-------------|---------|
| Per event | Limit per event type | 5 stop/min |
| Global | Total limit | 10 sounds/min |
| Burst | Allow burst, then limit | 5 burst, 1/min |
| Adaptive | Auto-adjust based on time | Higher at night |

### Configuration

```go
type RateLimitConfig struct {
    Enabled       bool              `json:"enabled"`
    GlobalLimit   int               `json:"global_limit"`   // per minute
    PerEvent      map[string]int    `json:"per_event"`      // event -> limit
    BurstSize     int               `json:"burst_size"`     // initial burst
    WindowSec     int               `json:"window_sec"`     // 60
    DropPolicy    string            `json:"drop_policy"`    // "oldest", "newest", "lowest_priority"
    QuietHoursMultiplier float64   `json:"quiet_hours_multiplier"` // reduce at night
}

type RateLimitState struct {
    EventCounts   map[string]int       `json:"event_counts"`
    GlobalCount   int                  `json:"global_count"`
    WindowStart   time.Time            `json:"window_start"`
}
```

### Commands

```bash
/ccbell:rate-limit enable           # Enable rate limiting
/ccbell:rate-limit disable          # Disable rate limiting
/ccbell:rate-limit set 10           # 10 sounds per minute
/ccbell:rate-limit set stop 5       # 5 stops per minute
/ccbell:rate-limit set burst 3      # 3 burst, then 1/min
/ccbell:rate-limit status           # Show rate limit status
/ccbell:rate-limit reset            # Reset counters
/ccbell:rate-limit quiet-hours 0.5  # 50% during quiet hours
```

### Output

```
$ ccbell:rate-limit status

=== Sound Rate Limiting ===

Status: Enabled
Global: 10/minute
Window: 60 seconds

Per-Event Limits:
  stop: 5/min
  permission_prompt: 10/min
  idle_prompt: 3/min
  subagent: 10/min

Burst: 3 sounds

Current Window:
  Used: 7/10 (Global)
  stop: 3/5
  permission_prompt: 3/10
  idle_prompt: 1/3

Remaining: 3 sounds
Resets in: 23s

[Configure] [Reset] [Disable]
```

---

## Audio Player Compatibility

Rate limiting doesn't play sounds:
- Controls when sounds play
- No player changes required

---

## Implementation

### Token Bucket Algorithm

```go
type RateLimiter struct {
    config  *RateLimitConfig
    state   *RateLimitState
    globalBucket *TokenBucket
    eventBuckets map[string]*TokenBucket
}

func NewRateLimiter(config *RateLimitConfig) *RateLimiter {
    return &RateLimiter{
        config:       config,
        state:        &RateLimitState{},
        globalBucket: NewTokenBucket(config.GlobalLimit, 60),
        eventBuckets: make(map[string]*TokenBucket),
    }
}

func (r *RateLimiter) Allow(eventType string) (bool, string) {
    // Check global limit
    if !r.globalBucket.TryConsume() {
        return false, "global rate limit exceeded"
    }

    // Check per-event limit
    bucket, ok := r.eventBuckets[eventType]
    if !ok {
        limit := r.config.PerEvent[eventType]
        if limit == 0 {
            limit = r.config.GlobalLimit
        }
        bucket = NewTokenBucket(limit, 60)
        r.eventBuckets[eventType] = bucket
    }

    if !bucket.TryConsume() {
        return false, fmt.Sprintf("rate limit exceeded for %s", eventType)
    }

    return true, ""
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

- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - Rate tracking
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
