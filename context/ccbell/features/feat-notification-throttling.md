---
name: Notification Throttling
description: Prevent notification spam by limiting the total number of notifications within a configurable time window
---

# Feature: Notification Throttling

Prevent notification spam by limiting the total number of notifications within a configurable time window.

## Table of Contents

1. [Summary](#summary)
2. [Benefit](#benefit)
3. [Priority & Complexity](#priority--complexity)
4. [Feasibility](#feasibility)
   - [Claude Code](#claude-code)
   - [Audio Player](#audio-player)
   - [External Dependencies](#external-dependencies)
5. [Usage in ccbell Plugin](#usage-in-ccbell-plugin)
6. [Repository Impact](#repository-impact)
   - [cc-plugins](#cc-plugins)
   - [ccbell](#ccbell)
7. [Implementation Plan](#implementation-plan)
   - [cc-plugins](#cc-plugins-1)
   - [ccbell](#ccbell-1)
8. [External Dependencies](#external-dependencies-1)
9. [Research Details](#research-details)
10. [Research Sources](#research-sources)

## Summary

Prevent notification spam by limiting the total number of notifications within a configurable time window. Reduces notification fatigue during busy work.

## Benefit

| Aspect | Description |
|--------|-------------|
| :bust_in_silhouette: User Impact | Fewer but meaningful notifications |
| :memo: Use Cases | Busy work periods, focus time |
| :dart: Value Proposition | Prevents sound fatigue, intelligent filtering |

## Priority & Complexity

| Aspect | Assessment |
|--------|------------|
| :rocket: Priority | `🟡` |
| :construction: Complexity | `🟢` |
| :warning: Risk Level | `🟢` |

## Feasibility

### Claude Code

Can this be implemented using Claude Code's native features?

| Feature | Description |
|---------|-------------|
| :keyboard: Commands | New `throttle` command with status/reset |
| :hook: Hooks | Uses existing hooks for event handling |
| :toolbox: Tools | Read, Write, Bash tools for throttle operations |

### Audio Player

How will audio playback be handled?

| Aspect | Description |
|--------|-------------|
| :speaker: afplay | Not affected - playback skipped when throttled |
| :computer: Platform Support | Cross-platform compatible |
| :musical_note: Audio Formats | No audio format changes |

### External Dependencies

Are external tools or libraries required?

No external dependencies - uses Go standard library.

## Usage in ccbell Plugin

Describe how this feature integrates with the existing ccbell plugin:

| Aspect | Description |
|--------|-------------|
| :hand: User Interaction | Users run `/ccbell:throttle` commands to view/reset |
| :wrench: Configuration | Adds `throttling` section to config |
| :gear: Default Behavior | Throttles notifications when limit exceeded |

## Repository Impact

### cc-plugins

Files that may be affected in cc-plugins:

| File | Description |
|------|-------------|
| `plugins/ccbell/.claude-plugin/plugin.json` | :package: Plugin manifest (version bump) |
| `plugins/ccbell/scripts/ccbell.sh` | :arrow_down: Download script (version sync) |
| `plugins/ccbell/hooks/hooks.json` | :hook: Hook definitions (no change) |
| `plugins/ccbell/commands/*.md` | :page_facing_up: Update configure.md with throttle section |
| `plugins/ccbell/sounds/` | :sound: Audio files (no change) |

### ccbell

Files that may be affected in ccbell:

| File | Description |
|------|-------------|
| `main.go` | :rocket: Main entry point (version bump) |
| `config/config.go` | :wrench: Add `throttling` section |
| `audio/player.go` | :speaker: Check throttling before playback |
| `hooks/*.go` | :hook: Hook implementations (no change) |

## Implementation Plan

### cc-plugins

Steps required in cc-plugins repository:

1. Update plugin.json version
2. Update ccbell.sh if needed
3. Add/update command documentation
4. Add/update hooks configuration
5. Add new sound files if applicable

### ccbell

Steps required in ccbell repository:

1. Add throttling section to config structure
2. Create internal/throttle/throttle.go
3. Implement ThrottleManager with Allow() method
4. Add throttle command with status/reset options
5. Modify main flow to check throttling before playing
6. Update version in main.go
7. Tag and release vX.X.X
8. Sync version to cc-plugins

## External Dependencies

| Dependency | Version | Purpose | Required |
|------------|---------|---------|----------|
| None | | | `➖` |

## Status

| Status | Description |
|--------|-------------|
| ✅ | macOS supported |
| ✅ | Linux supported |
| ✅ | No external dependencies (uses Go stdlib) |
| ✅ | Cross-platform compatible |

## Research Details

### Claude Code Plugins

Plugin manifest supports commands. New throttle command can be added.

### Claude Code Hooks

No new hooks needed - throttling check integrated into main flow.

### Audio Playback

Playback is skipped when throttling limit is exceeded.

### Throttling Implementation Patterns

#### Sliding Window Algorithm
```go
type ThrottleManager struct {
    maxCount  int
    window    time.Duration
    events    []time.Time
    mu        sync.Mutex
}

func (t *ThrottleManager) Allow() bool {
    t.mu.Lock()
    defer t.mu.Unlock()

    now := time.Now()
    cutoff := now.Add(-t.window)

    // Remove old events
    var valid []time.Time
    for _, e := range t.events {
        if e.After(cutoff) {
            valid = append(valid, e)
        }
    }
    t.events = valid

    if len(t.events) >= t.maxCount {
        return false // Throttled
    }

    t.events = append(t.events, now)
    return true
}
```

#### Token Bucket Algorithm
```go
type TokenBucket struct {
    tokens     float64
    capacity   float64
    rate       float64
    lastUpdate time.Time
    mu         sync.Mutex
}

func (tb *TokenBucket) Allow() bool {
    tb.mu.Lock()
    defer tb.mu.Unlock()

    now := time.Now()
    elapsed := now.Sub(tb.lastUpdate).Seconds()
    tb.tokens = math.Min(tb.capacity, tb.tokens+elapsed*tb.rate)
    tb.lastUpdate = now

    if tb.tokens >= 1 {
        tb.tokens--
        return true
    }
    return false
}
```

#### Sliding Log with Redis (Distributed)
- **Use Case**: Multi-instance environments
- **Library**: https://github.com/redis/go-redis
- **Commands**: ZADD, ZREMRANGEBYSCORE, ZCARD

```go
func RedisThrottle(client *redis.Client, key string, limit int, window time.Duration) bool {
    now := time.Now().UnixMilli()
    windowStart := now - window.Milliseconds()

    pipe := client.Pipeline()

    // Add current event
    pipe.ZAdd(ctx, key, &redis.Z{
        Score:  float64(now),
        Member: fmt.Sprintf("%d", now),
    })

    // Remove old events
    pipe.ZRemRangeByScore(ctx, key, "-inf", fmt.Sprintf("%d", windowStart))

    // Count remaining
    countCmd := pipe.ZCard(ctx, key)

    _, _ = pipe.Exec(ctx)

    return int(countCmd.Val()) <= limit
}
```

### Throttling Features

- **Max count per time window** (e.g., 10 notifications per 5 minutes)
- **Burst limit** for short periods (e.g., max 3 in 30 seconds)
- **Action when limit exceeded** (silence/warn/silent)
- **Reset command** to clear throttle windows
- **Granular control** by event type
- **Distributed throttling** (Redis) for multi-instance

### Throttling Strategies

| Strategy | Description | Use Case |
|----------|-------------|----------|
| **Sliding Window** | Count events in rolling time window | General use |
| **Token Bucket** | Allow burst with gradual refill | Burst handling |
| **Fixed Window** | Simple count per hour/day | Basic rate limiting |
| **Distributed** | Redis-based for multi-instance | Server environments |

## Research Sources

| Source | Description |
|--------|-------------|
| [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) | :books: State management |
| [Cooldown logic](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) | :books: Cooldown patterns |
| [Redis go-redis](https://github.com/redis/go-redis) | :books: Redis client for distributed throttling |
| [Rate Limiting Patterns](https://github.com/uber-go/ratelimit) | :books: Uber's rate limiter |
| [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) | :books: Main flow |
