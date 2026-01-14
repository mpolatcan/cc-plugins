# Feature: Sound Batching

Batch process multiple sounds for efficiency.

## Summary

Process multiple sounds in a single operation for analysis, conversion, or backup.

## Motivation

- Analyze multiple sounds at once
- Convert multiple sound formats in batch
- Efficient workflow for sound library management

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Batch Operations

| Operation | Description | Example |
|-----------|-------------|---------|
| Analyze | Get info for multiple sounds | `--analyze *.aiff` |
| Convert | Convert format for multiple | `--convert wav` |
| Normalize | Normalize volume for all | `--normalize` |
| Backup | Backup sound collection | `--backup /path` |
| Validate | Check sound integrity | `--validate` |

### Implementation

```go
type BatchOperation string

const (
    BatchAnalyze    BatchOperation = "analyze"
    BatchConvert    BatchOperation = "convert"
    BatchNormalize  BatchOperation = "normalize"
    BatchBackup     BatchOperation = "backup"
    BatchValidate   BatchOperation = "validate"
)

type BatchConfig struct {
    Operation   BatchOperation `json:"operation"`
    SourceDir   string         `json:"source_dir"`
    Pattern     string         `json:"pattern"`     // glob pattern
    TargetDir   string         `json:"target_dir"`  // for convert/backup
    Format      string         `json:"format"`      // for convert
    Parallel    int            `json:"parallel"`    // max concurrent
}

type BatchResult struct {
    Total      int            `json:"total"`
    Success    int            `json:"success"`
    Failed     int            `json:"failed"`
    Results    []SoundResult  `json:"results"`
    Duration   time.Duration  `json:"duration"`
}
```

### Commands

```bash
/ccbell:batch analyze *.aiff                    # Analyze all sounds
/ccbell:batch convert --format wav --output out # Convert to WAV
/ccbell:batch normalize sounds/                 # Normalize volume
/ccbell:batch backup --destination ~/backup     # Backup sounds
/ccbell:batch validate --pattern "bundled:*"    # Validate bundled
/ccbell:batch --parallel 4 analyze "**/*.aiff"  # Parallel processing
```

### Output

```
$ ccbell:batch analyze bundled:*

=== Batch Analysis ===

Processing: 15 sounds
Pattern: bundled:*
Parallel: 4

[==========] 100% 15/15 (2.34s)

Results:
  bundled:stop              OK (1.234s, -18.5dB)
  bundled:permission_prompt OK (0.567s, -15.2dB)
  bundled:idle_prompt       OK (0.890s, -20.1dB)
  ...

Summary:
  Total: 15
  Success: 15
  Failed: 0

  Total duration: 2.34s
  Avg per sound: 156ms
```

---

## Audio Player Compatibility

Batch operations don't play sounds:
- Analysis uses ffprobe
- Conversion uses ffmpeg
- No player changes required

---

## Implementation

### Parallel Processing

```go
func (b *BatchProcessor) Run(config *BatchConfig) (*BatchResult, error) {
    result := &BatchResult{
        Results: make([]SoundResult, 0),
    }

    files, err := globFiles(config.SourceDir, config.Pattern)
    if err != nil {
        return nil, err
    }

    semaphore := make(chan struct{}, config.Parallel)
    var wg sync.WaitGroup

    for _, file := range files {
        wg.Add(1)
        semaphore <- struct{}{}

        go func(path string) {
            defer wg.Done()
            defer func() { <-semaphore }()

            res := b.processFile(path, config.Operation, config)
            result.Results = append(result.Results, *res)
        }(file)
    }

    wg.Wait()

    // Summarize results
    result.Total = len(files)
    result.Success = countSuccess(result.Results)
    result.Failed = result.Total - result.Success

    return result, nil
}
```

### Conversion Pipeline

```go
func (b *BatchProcessor) convertSound(path, outputDir, format string) error {
    outputPath := filepath.Join(outputDir, basename(path)+"."+format)

    cmd := exec.Command("ffmpeg", "-y", "-i", path,
        "-ar", "44100", "-ac", "2",
        outputPath)

    return cmd.Run()
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ffmpeg | External tool | Free | For conversion |
| glob | Go standard | Free | File pattern matching |

---

## References

### ccbell Implementation Research

- [Player packages](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L27-L32) - ffprobe/ffmpeg available
- [Sound resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L134-L155) - Sound path handling

### Research Sources

- [FFmpeg batch processing](https://ffmpeg.org/ffmpeg.html)
- [Go glob patterns](https://pkg.go.dev/path/filepath#Match)

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via ffmpeg |
| Linux | ✅ Supported | Via ffmpeg |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
