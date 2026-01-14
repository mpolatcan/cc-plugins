# Feature: Sound Event Git Monitor

Play sounds for git repository operations and version control events.

## Summary

Monitor git operations, repository changes, and version control events, playing sounds for git activity.

## Motivation

- Commit notifications
- Push/pull feedback
- Merge conflict alerts
- Branch change detection

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 2-3 days |

---

## Technical Feasibility

### Git Events

| Event | Description | Example |
|-------|-------------|---------|
| Commit | New commit created | git commit -m "fix: bug" |
| Push | Changes pushed | git push origin main |
| Pull | Changes fetched | git pull |
| Merge | Branch merged | git merge feature |
| Conflict | Merge conflict | Conflict detected |
| Clone | Repository cloned | git clone url |

### Configuration

```go
type GitMonitorConfig struct {
    Enabled       bool              `json:"enabled"`
    WatchRepos    []string          `json:"watch_repos"` // Repository paths
    SoundOnCommit bool              `json:"sound_on_commit"`
    SoundOnPush   bool              `json:"sound_on_push"`
    SoundOnPull   bool              `json:"sound_on_pull"`
    SoundOnMerge  bool              `json:"sound_on_merge"`
    Sounds        map[string]string `json:"sounds"`
    PollInterval  int               `json:"poll_interval_sec"` // 10 default
}

type GitEvent struct {
    RepoPath   string
    EventType  string // "commit", "push", "pull", "merge", "clone"
    Branch     string
    CommitHash string
    Message    string
}
```

### Commands

```bash
/ccbell:git status           # Show git status
/ccbell:git add ~/project    # Add repo to watch
/ccbell:git remove ~/project # Remove repo
/ccbell:git sound commit <sound>
/ccbell:git sound push <sound>
/ccbell:git test             # Test git sounds
```

### Output

```
$ ccbell:git status

=== Sound Event Git Monitor ===

Status: Enabled
Commit Sounds: Yes
Push Sounds: Yes
Pull Sounds: Yes

Watched Repos: 2

[1] ~/project
    Current Branch: main
    Last Commit: 2 hours ago
    Uncommitted: 3
    Sound: bundled:stop

[2] ~/work/project
    Current Branch: feature/auth
    Last Commit: 5 min ago
    Uncommitted: 0
    Sound: bundled:stop

Recent Events:
  [1] ~/project: Commit (2 hours ago)
       "fix: resolve memory leak"
  [2] ~/work/project: Push (5 min ago)
       3 commits to main
  [3] ~/project: Pull (1 day ago)
       Updated 5 files

Sound Settings:
  Commit: bundled:stop
  Push: bundled:stop
  Pull: bundled:stop
  Merge: bundled:stop
  Conflict: bundled:stop

[Configure] [Add Repo] [Test All]
```

---

## Audio Player Compatibility

Git monitoring doesn't play sounds directly:
- Monitoring feature using git commands
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Git Monitor

```go
type GitMonitor struct {
    config        *GitMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    lastCommit    map[string]string // repo -> commit hash
}

func (m *GitMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastCommit = make(map[string]string)
    go m.monitor()
}

func (m *GitMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkRepos()
        case <-m.stopCh:
            return
        }
    }
}

func (m *GitMonitor) checkRepos() {
    for _, repoPath := range m.config.WatchRepos {
        m.checkRepo(repoPath)
    }
}

func (m *GitMonitor) checkRepo(repoPath string) {
    // Expand home directory
    if strings.HasPrefix(repoPath, "~") {
        repoPath = filepath.Join(os.Getenv("HOME"), repoPath[1:])
    }

    // Get current branch
    branch, err := m.getBranch(repoPath)
    if err != nil {
        return
    }

    // Get latest commit
    commit, err := m.getLatestCommit(repoPath)
    if err != nil {
        return
    }

    lastCommit := m.lastCommit[repoPath]
    if lastCommit != "" && lastCommit != commit {
        // New commit detected
        m.onNewCommit(repoPath, commit)
    }

    // Check for uncommitted changes
    hasChanges, err := m.hasUncommittedChanges(repoPath)
    if err == nil && hasChanges && !m.repoState[repoPath].HasUncommitted {
        m.repoState[repoPath].HasUncommitted = true
        // Could play a subtle sound for uncommitted changes
    }

    m.lastCommit[repoPath] = commit
}

func (m *GitMonitor) getBranch(repoPath string) (string, error) {
    cmd := exec.Command("git", "rev-parse", "--abbrev-ref", "HEAD")
    cmd.Dir = repoPath
    output, err := cmd.Output()
    if err != nil {
        return "", err
    }
    return strings.TrimSpace(string(output)), nil
}

func (m *GitMonitor) getLatestCommit(repoPath string) (string, error) {
    cmd := exec.Command("git", "rev-parse", "HEAD")
    cmd.Dir = repoPath
    output, err := cmd.Output()
    if err != nil {
        return "", err
    }
    return strings.TrimSpace(string(output)), nil
}

func (m *GitMonitor) hasUncommittedChanges(repoPath string) (bool, error) {
    cmd := exec.Command("git", "status", "--porcelain")
    cmd.Dir = repoPath
    output, err := cmd.Output()
    if err != nil {
        return false, err
    }
    return len(output) > 0, nil
}

func (m *GitMonitor) onNewCommit(repoPath, commit string) {
    if !m.config.SoundOnCommit {
        return
    }

    sound := m.config.Sounds["commit"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *GitMonitor) onPush(repoPath, branch string) {
    if !m.config.SoundOnPush {
        return
    }

    sound := m.config.Sounds["push"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *GitMonitor) onPull(repoPath string) {
    if !m.config.SoundOnPull {
        return
    }

    sound := m.config.Sounds["pull"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}

func (m *GitMonitor) onMerge(repoPath, branch string) {
    if !m.config.SoundOnMerge {
        return
    }

    sound := m.config.Sounds["merge"]
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| git | System Tool | Free | Version control |
| exec | Go Stdlib | Free | Command execution |

---

## References

### ccbell Implementation Research

- [Player implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Sound playback
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling
- [State management](https://github.com/mpolatcan/ccbell/blob/main/internal/state/state.go) - State tracking

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | Supported | Uses git command |
| Linux | Supported | Uses git command |
| Windows | Not Supported | ccbell only supports macOS/Linux |
