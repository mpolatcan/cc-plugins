# Feature: Sound Recommendation Engine

Suggest sounds based on usage patterns.

## Summary

Analyze usage and recommend alternative or new sounds.

## Motivation:

- Discover new sounds
- Improve notification experience
- Data-driven sound selection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 4-5 days |

---

## Technical Feasibility

### Recommendation Types

| Type | Description | Data Source |
|------|-------------|-------------|
| Similar sounds | Alternatives to current | Audio fingerprint |
| Popular sounds | Frequently used | Usage analytics |
| Related events | Sounds for related events | Event patterns |
| Time-based | Sounds for current time | Time patterns |

### Implementation

```go
type RecommendationEngine struct {
    analyticsStore *AnalyticsStore
    soundLibrary   *SoundLibrary
    fingerprintDB  *FingerprintDB
}

type Recommendation struct {
    SoundID       string
    SoundPath     string
    Reason        string  // "similar", "popular", "related", "time"
    Score         float64 // 0-1
    MatchDetails  string
}
```

### Recommendation Logic

```go
func (e *RecommendationEngine) GetRecommendations(eventType string, count int) []*Recommendation {
    recommendations := []*Recommendation{}

    // 1. Similar sounds
    currentSound := e.getCurrentSound(eventType)
    similar := e.findSimilarSounds(currentSound, 3)
    for _, s := range similar {
        recommendations = append(recommendations, &Recommendation{
            SoundID:      s.ID,
            SoundPath:    s.Path,
            Reason:       "similar",
            Score:        s.Similarity,
            MatchDetails: fmt.Sprintf("%.0f%% audio similarity", s.Similarity*100),
        })
    }

    // 2. Popular sounds for event
    popular := e.getPopularSoundsForEvent(eventType, 2)
    for _, s := range popular {
        recommendations = append(recommendations, &Recommendation{
            SoundID:      s.ID,
            SoundPath:    s.Path,
            Reason:       "popular",
            Score:        s.Popularity,
            MatchDetails: fmt.Sprintf("%d plays", s.PlayCount),
        })
    }

    // 3. Time-based suggestions
    timeBased := e.getTimeBasedRecommendations(eventType, time.Now())
    for _, s := range timeBased {
        recommendations = append(recommendations, &Recommendation{
            SoundID:      s.ID,
            SoundPath:    s.Path,
            Reason:       "time",
            Score:        0.7,
            MatchDetails: "Popular during this time",
        })
    }

    // Sort by score and return top N
    sort.Slice(recommendations, func(i, j int) bool {
        return recommendations[i].Score > recommendations[j].Score
    })

    return recommendations[:count]
}
```

### Commands

```bash
/ccbell:recommend stop              # Recommend for stop event
/ccbell:recommend --count 5         # Top 5 recommendations
/ccbell:recommend similar bundled:stop
/ccbell:recommend popular permission_prompt
/ccbell:recommend install <sound_id>  # Install recommended sound
/ccbell:feedback --thumbs-up <sound>  # Improve recommendations
```

### Output

```
$ ccbell:recommend stop

=== Recommendations for 'stop' ===

[1] custom:gentle-chime (Similar: 94%)
    Reason: Similar audio characteristics
    [Install] [Preview] [Dismiss]

[2] packs/zen-bells/ending (Popular: 456 plays)
    Reason: Popular for stop events
    [Install] [Preview] [Dismiss]

[3] bundled:soft-notification (Similar: 87%)
    Reason: Similar audio characteristics
    [Install] [Preview] [Dismiss]

[4] custom:my-alternative (Time: Evening)
    Reason: Popular during evening hours
    [Install] [Preview] [Dismiss]

Showing 4 of 12 recommendations
[Next] [Prev]
```

---

## Audio Player Compatibility

Recommendation engine doesn't play sounds:
- Analytics-based suggestions
- No player changes required
- Uses existing sound paths

---

## Implementation

### Fingerprint Matching

```go
func (e *RecommendationEngine) findSimilarSounds(sound *SoundMetadata, limit int) []*SoundMetadata {
    fp := e.fingerprintDB.Get(sound.Path)
    if fp == nil {
        fp = computeFingerprint(sound.Path)
        e.fingerprintDB.Store(sound.Path, fp)
    }

    matches := e.fingerprintDB.FindSimilar(fp, 0.8)
    // Return top N similar sounds
}
```

### Feedback Loop

```go
func (e *RecommendationEngine) recordFeedback(soundID string, helpful bool) {
    // Improve recommendations based on feedback
    e.feedbackStore.Record(soundID, helpful)

    // Adjust future recommendations
    e.recalculateWeights()
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

- [Analytics store](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - Usage tracking
- [Sound library](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Sound references
- [Fingerprint concepts](https://en.wikipedia.org/wiki/Acoustic_fingerprint)

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
