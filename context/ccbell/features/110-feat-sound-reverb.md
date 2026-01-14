# Feature: Sound Reverb

Add reverb effects to sounds.

## Summary

Apply reverb effects to sounds for richer audio.

## Motivation

- Enhance sound quality
- Create atmosphere
- Normalize sound environment

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Reverb Presets

| Preset | Description | Room Size |
|--------|-------------|-----------|
| Small | Small room | 10m² |
| Medium | Medium room | 30m² |
| Large | Large hall | 100m² |
| Cathedral | Large cathedral | 500m² |
| Custom | Custom parameters | - |

### Configuration

```go
type ReverbConfig struct {
    Enabled     bool    `json:"enabled"`
    Preset      string  `json:"preset"`        // preset name
    RoomSize    float64 `json:"room_size"`     // 0-1
    Damping     float64 `json:"damping"`       // 0-1
    WetDryMix   float64 `json:"wet_dry_mix"`   // 0-1 (reverb vs original)
    PreDelay    int     `json:"pre_delay_ms"`  // ms
    DecayTime   float64 `json:"decay_time"`    // seconds
}

type ReverbPreset struct {
    Name        string  `json:"name"`
    RoomSize    float64 `json:"room_size"`
    Damping     float64 `json:"damping"`
    PreDelay    int     `json:"pre_delay_ms"`
    DecayTime   float64 `json:"decay_time"`
}
```

### Commands

```bash
/ccbell:reverb enable                 # Enable reverb
/ccbell:reverb disable                # Disable reverb
/ccbell:reverb set preset large       # Large hall preset
/ccbell:reverb set room-size 0.7      # Custom room size
/ccbell:reverb set wet-dry 0.3        # 30% reverb
/ccbell:reverb preview                # Preview reverb
/ccbell:reverb apply input.aiff output.aiff
```

### Output

```
$ ccbell:reverb set preset large

=== Sound Reverb ===

Status: Enabled
Preset: Large Hall

Parameters:
  Room Size: 0.8
  Damping: 0.5
  Wet/Dry: 0.3 (30% reverb)
  Pre-Delay: 20ms
  Decay Time: 2.5s

Preview:
  [============] Playing with reverb
  [████████████] Original

[Apply] [Presets] [Customize] [Disable]
```

---

## Audio Player Compatibility

Reverb doesn't play sounds:
- Uses ffmpeg for effects
- No player changes required
- Pre-processing only

---

## Implementation

### FFmpeg Reverb

```go
func (r *ReverbManager) ApplyReverb(inputPath, outputPath string, config *ReverbConfig) error {
    // Build reverb filter
    filter := r.buildReverbFilter(config)

    args := []string{"-y", "-i", inputPath}
    if filter != "" {
        args = append(args, "-af", filter)
    }
    args = append(args, outputPath)

    return exec.Command("ffmpeg", args...).Run()
}

func (r *ReverbManager) buildReverbFilter(config *ReverbConfig) string {
    if !config.Enabled {
        return ""
    }

    return fmt.Sprintf("averbate=room_size=%.2f:decay_time=%.1f:damping=%.2f:wet_gain=0:wet_only=false",
        config.RoomSize,
        config.DecayTime,
        config.Damping,
    )
}
```

### Custom Reverb

```go
func (r *ReverbManager) buildCustomReverb(config *ReverbConfig) string {
    return fmt.Sprintf("averbate=room_size=%.2f:hf_damping=%.2f:decay_time=%.1f:pre_delay=%d:wet_gain=%.2f:wet_level=%.2f",
        config.RoomSize,
        config.Damping,
        config.DecayTime,
        config.PreDelay,
        config.WetDryMix, // wet gain
        config.WetDryMix, // wet level
    )
}
```

### Preset Selection

```go
var reverbPresets = map[string]ReverbPreset{
    "small": {
        Name:        "Small Room",
        RoomSize:    0.3,
        Damping:     0.7,
        PreDelay:    10,
        DecayTime:   0.5,
    },
    "medium": {
        Name:        "Medium Room",
        RoomSize:    0.5,
        Damping:     0.5,
        PreDelay:    20,
        DecayTime:   1.0,
    },
    "large": {
        Name:        "Large Hall",
        RoomSize:    0.8,
        Damping:     0.3,
        PreDelay:    30,
        DecayTime:   2.5,
    },
    "cathedral": {
        Name:        "Cathedral",
        RoomSize:    0.95,
        Damping:     0.1,
        PreDelay:    50,
        DecayTime:   5.0,
    },
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ffmpeg | External tool | Free | Audio reverb |

---

## References

### ccbell Implementation Research

- [Player packages](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L27-L32) - ffmpeg available

### Research Sources

- [FFmpeg averbate](https://ffmpeg.org/ffmpeg-filters.html#averbate)
- [Audio reverb](https://en.wikipedia.org/wiki/Reverberation)

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via ffmpeg |
| Linux | ✅ Supported | Via ffmpeg |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
