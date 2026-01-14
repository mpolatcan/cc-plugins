# Feature: Sound Metadata Editor

Edit sound metadata and tags.

## Summary

View and edit metadata tags embedded in sound files for organization and search.

## Motivation

- Organize sound library
- Add custom tags
- Improve searchability
- Sound documentation

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Metadata Fields

| Field | Type | Description |
|-------|------|-------------|
| Title | string | Sound name |
| Artist | string | Creator |
| Album | string | Collection name |
| Genre | string | Sound category |
| Comment | string | Notes |
| Tags | []string | Searchable tags |
| Rating | int | 1-5 star rating |

### Implementation

```go
type SoundMetadata struct {
    Title   string   `json:"title"`
    Artist  string   `json:"artist"`
    Album   string   `json:"album"`
    Genre   string   `json:"genre"`
    Comment string   `json:"comment"`
    Tags    []string `json:"tags"`
    Rating  int      `json:"rating"` // 1-5
    Year    int      `json:"year"`
    BPM     int      `json:"bpm"`
}

type MetadataEdit struct {
    Field    string `json:"field"`
    Value    string `json:"value"`
    Add      bool   `json:"add"`      // for tags
    Remove   bool   `json:"remove"`   // for tags
}
```

### Commands

```bash
/ccbell:meta show bundled:stop              # Show metadata
/ccbell:meta show bundled:stop --json       # JSON output
/ccbell:meta set title "Stop Bell"           # Set title
/ccbell:meta add tags "notification,alert"   # Add tags
/ccbell:meta remove tags "old"              # Remove tags
/ccbell:meta set rating 5                   # Set rating
/ccbell:meta clear comment                  # Clear field
/ccbell:meta batch --pattern "bundled:*" --set genre=notification
```

### Output

```
$ ccbell:meta show bundled:stop

=== Sound Metadata ===

File: bundled:stop
Path: ~/.local/share/ccbell/sounds/bundled/stop.aiff

Title: Stop Bell
Artist: CCBell
Album: Default Sounds
Genre: Notification
Tags: [stop, alert, system]
Rating: ★★★★☆ (4)
Year: 2024
BPM: -
Comment: Standard stop notification sound

[Edit] [Clear] [Done]
```

---

## Audio Player Compatibility

Metadata editor doesn't play sounds:
- Metadata reading via ffprobe
- Metadata writing via external tool
- No player changes required

---

## Implementation

### Read Metadata

```go
func (m *MetadataEditor) ReadMetadata(soundPath string) (*SoundMetadata, error) {
    cmd := exec.Command("ffprobe", "-v", "quiet",
        "-print_format", "json",
        "-show_format",
        soundPath)

    output, err := cmd.Output()
    if err != nil {
        return nil, err
    }

    var probeResult ffprobeResult
    if err := json.Unmarshal(output, &probeResult); err != nil {
        return nil, err
    }

    format := probeResult.Format
    tags := parseTags(format.Tags)

    return &SoundMetadata{
        Title:   format.Tags["title"],
        Artist:  format.Tags["artist"],
        Album:   format.Tags["album"],
        Genre:   format.Tags["genre"],
        Comment: format.Tags["comment"],
        Tags:    tags,
        Rating:  parseRating(format.Tags),
        Year:    parseYear(format.Tags["date"]),
    }, nil
}
```

### Write Metadata

```go
func (m *MetadataEditor) WriteMetadata(soundPath string, metadata *SoundMetadata) error {
    args := []string{
        "-i", soundPath,
        "-metadata", "title="+metadata.Title,
        "-metadata", "artist="+metadata.Artist,
        "-metadata", "album="+metadata.Album,
        "-metadata", "genre="+metadata.Genre,
        "-metadata", "comment="+metadata.Comment,
    }

    // Add tags
    for _, tag := range metadata.Tags {
        args = append(args, "-metadata", "tag="+tag)
    }

    outputPath := soundPath + ".tmp"
    args = append(args, "-c", "copy", outputPath)

    cmd := exec.Command("ffmpeg", args...)
    return cmd.Run()
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| ffprobe | External tool | Free | Metadata reading |
| ffmpeg | External tool | Free | Metadata writing |

---

## References

### ccbell Implementation Research

- [Player packages](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L27-L32) - ffprobe available
- [Sound resolution](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L134-L155) - Sound paths

### Research Sources

- [FFmpeg metadata](https://ffmpeg.org/ffmpeg-formats.html#Metadata)
- [ID3 tags](https://id3.org/)

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Via ffprobe/ffmpeg |
| Linux | ✅ Supported | Via ffprobe/ffmpeg |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
