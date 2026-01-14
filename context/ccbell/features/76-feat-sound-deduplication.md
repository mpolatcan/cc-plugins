# Feature: Sound Deduplication

Detect and remove duplicate or nearly identical sound files.

## Summary

Identify and manage duplicate sounds to save space and reduce confusion.

## Motivation

- Free disk space
- Reduce sound selection confusion
- Clean up sound library

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Duplicate Detection Methods

| Method | Accuracy | Speed | Tool |
|--------|----------|-------|------|
| File hash | Exact matches | Fast | Native |
| Audio fingerprint | Similar audio | Slow | sox/ffprobe |
| Waveform comparison | Visual similarity | Medium | Custom |

### Implementation

```go
type DeduplicationConfig struct {
    Enabled      bool    `json:"enabled"`
    Threshold    float64 `json:"threshold"`  // Similarity threshold 0-1
    Method       string  `json:"method"`     // "hash", "fingerprint", "waveform"
    AutoDelete   bool    `json:"auto_delete"`
    KeepOriginal string  `json:"keep_original"`  // "largest", "newest", "oldest"
}
```

### Hash-based Detection

```go
func findDuplicatesByHash(soundDir string) (map[string][]string, error) {
    files := listSoundFiles(soundDir)
    duplicates := make(map[string][]string)
    hashIndex := make(map[string]string)

    for _, file := range files {
        hash, err := computeFileHash(file.Path)
        if err != nil {
            continue
        }

        if existing, ok := hashIndex[hash]; ok {
            duplicates[hash] = append(duplicates[hash], file.Path)
            duplicates[hash] = append(duplicates[hash], existing)
        } else {
            hashIndex[hash] = file.Path
        }
    }

    return duplicates, nil
}
```

### Audio Fingerprint Detection

```go
func findDuplicatesByFingerprint(soundDir string) (map[string][]string, error) {
    files := listSoundFiles(soundDir)
    fingerprints := make(map[string][]string)
    index := make(map[string]string)

    for _, file := range files {
        fp, err := computeFingerprint(file.Path)
        if err != nil {
            continue
        }

        // Check for similar fingerprints
        for existingFp, existingPath := range index {
            similarity := compareFingerprints(fp, existingFp)
            if similarity >= deduplicationConfig.Threshold {
                key := fmt.Sprintf("sim_%s_%s", fp[:8], existingFp[:8])
                fingerprints[key] = []string{file.Path, existingPath}
            }
        }

        if _, exists := index[fp]; !exists {
            index[fp] = file.Path
        }
    }

    return fingerprints, nil
}
```

### Commands

```bash
/ccbell:dedup scan                   # Scan for duplicates
/ccbell:dedup scan --method hash     # Hash-based only
/ccbell:dedup scan --method audio    # Audio fingerprint
/ccbell:dedup list                   # List found duplicates
/ccbell:dedup remove file1 file2     # Remove specific duplicates
/ccbell:dedup remove --keep newest   # Remove all but newest
/ccbell:dedup dry-run                # Preview without changes
```

### Output

```
$ ccbell:dedup scan

Scanning sound library...

=== Duplicates Found ===

Exact matches:
  [Hash: abc123def456]
    - custom/alert.aiff (245 KB, Jan 10)
    - custom/alert_copy.aiff (245 KB, Jan 12)
  [Hash: xyz789abc123]
    - packs/zen/ding.aiff (128 KB)
    - packs/zen/ding_copy.aiff (128 KB)

Similar audio (90%+ similarity):
  [Similarity: 94%]
    - custom/chime.aiff (156 KB)
    - custom/bell.aiff (158 KB)

Summary:
  Exact duplicates: 4 files (2 pairs)
  Similar audio: 2 files (1 pair)
  Space to free: 373 KB

Remove duplicates? [y/n]:
```

---

## Audio Player Compatibility

Deduplication doesn't interact with audio playback:
- File analysis and management
- No player changes required
- Uses existing sound paths after cleanup

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| sox | Optional | Free | For audio fingerprinting |
| None | Native | Free | Hash-based works without deps |

---

## References

### Research Sources

- [File hash computation](https://pkg.go.dev/crypto/sha256)
- [Audio fingerprinting concepts](https://en.wikipedia.org/wiki/Acoustic_fingerprint)

### ccbell Implementation Research

- [Sound resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L134-L155) - Sound path handling
- [File operations](https://pkg.go.dev/os) - Go file management
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Deduplication config

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Full detection |
| Linux | ✅ Supported | Full detection |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
