# Feature: Sound Event Git Repository Monitor

Play sounds for git repository events, push notifications, and branch changes.

## Summary

Monitor git repositories for push events, branch changes, merge status, and pull request updates, playing sounds for git events.

## Motivation

- Git awareness
- Push notifications
- Branch change alerts
- Merge feedback
- Repository activity monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Git Repository Events

| Event | Description | Example |
|-------|-------------|---------|
| Push Received | New commits pushed | 5 commits |
| New Branch | Branch created | feature/x |
| Branch Deleted | Branch removed | feature/x |
| Tag Created | Annotated tag | v1.0.0 |
| Merge Conflict | Conflict detected | conflict |
| Pull Request | PR updated | #123 |

### Configuration

```go
type GitRepositoryMonitorConfig struct {
    Enabled        bool              `json:"enabled"`
    WatchRepos     []string          `json:"watch_repos"` // paths to git repos
    WatchBranches  []string          `json:"watch_branches"` // branch patterns
    SoundOnPush    bool              `json:"sound_on_push"`
    SoundOnBranch  bool              `json:"sound_on_branch"`
    SoundOnMerge   bool              `json:"sound_on_merge"`
    SoundOnTag     bool              `json:"sound_on_tag"`
    Sounds         map[string]string `json:"sounds"`
    PollInterval   int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:git status                  # Show git status
/ccbell:git add ~/projects/myrepo   # Add repo to watch
/ccbell:git sound push <sound>
/ccbell:git test                    # Test git sounds
```

### Output

```
$ ccbell:git status

=== Sound Event Git Repository Monitor ===

Status: Enabled
Watch Repositories: 3

Repository Status:

[1] ~/projects/myrepo (main)
    Status: CLEAN
    Branch: main
    Commits: 5 ahead
    Untracked: 0
    Sound: bundled:git-repo

[2] ~/projects/ccbell (develop)
    Status: DIRTY *** UNCOMMITTED ***
    Branch: develop
    Modified: 5 files
    Sound: bundled:git-ccbell *** WARNING ***

[3] ~/projects/plugins (feature/new)
    Status: NEW BRANCH
    Branch: feature/new
    Created: 2 hours ago
    Sound: bundled:git-branch

Recent Events:

[1] ~/projects/ccbell: Uncommitted Changes (5 min ago)
       5 modified files
       Sound: bundled:git-dirty
  [2] ~/projects/myrepo: Push Received (1 hour ago)
       5 new commits
       Sound: bundled:git-push
  [3] ~/projects/plugins: New Branch (2 hours ago)
       feature/new created
       Sound: bundled:git-branch

Git Statistics:
  Total Repos: 3
  Clean: 2
  Dirty: 1
  New Branches: 1

Sound Settings:
  Push: bundled:git-push
  Branch: bundled:git-branch
  Merge: bundled:git-merge
  Dirty: bundled:git-dirty

[Configure] [Add Repository] [Test All]
```

---

## Audio Player Compatibility

Git monitoring doesn't play sounds directly:
- Monitoring feature using git command
- No player changes required
- Uses existing audio player infrastructure
- Uses afplay (macOS) or mpv/paplay/aplay/ffplay (Linux)

---

## Implementation

### Git Repository Monitor

```go
type GitRepositoryMonitor struct {
    config        *GitRepositoryMonitorConfig
    player        *audio.Player
    running       bool
    stopCh        chan struct{}
    repoState     map[string]*RepoInfo
    lastEventTime map[string]time.Time
}

type RepoInfo struct {
    Path       string
    Branch     string
    Status     string // "clean", "dirty", "ahead", "behind"
    CommitsAhead int
    CommitsBehind int
    ModifiedFiles int
    UntrackedFiles int
    LastCheck  time.Time
}

func (m *GitRepositoryMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.repoState = make(map[string]*RepoInfo)
    m.lastEventTime = make(map[string]time.Time)
    go m.monitor()
}

func (m *GitRepositoryMonitor) monitor() {
    ticker := time.NewTicker(time.Duration(m.config.PollInterval) * time.Second)
    defer ticker.Stop()

    // Initial snapshot
    m.snapshotRepoState()

    for {
        select {
        case <-ticker.C:
            m.checkRepoState()
        case <-m.stopCh:
            return
        }
    }
}

func (m *GitRepositoryMonitor) snapshotRepoState() {
    m.checkRepoState()
}

func (m *GitRepositoryMonitor) checkRepoState() {
    for _, repoPath := range m.config.WatchRepos {
        info := m.getRepoInfo(repoPath)
        if info != nil {
            m.processRepoStatus(info)
        }
    }
}

func (m *GitRepositoryMonitor) getRepoInfo(repoPath string) *RepoInfo {
    // Check if directory is a git repo
    gitDir := filepath.Join(repoPath, ".git")
    if _, err := os.Stat(gitDir); err != nil {
        return nil
    }

    info := &RepoInfo{
        Path:      repoPath,
        LastCheck: time.Now(),
    }

    // Get current branch
    cmd := exec.Command("git", "rev-parse", "--abbrev-ref", "HEAD")
    cmd.Dir = repoPath
    branchOutput, _ := cmd.Output()
    info.Branch = strings.TrimSpace(string(branchOutput))

    // Check for uncommitted changes
    cmd = exec.Command("git", "status", "--porcelain")
    cmd.Dir = repoPath
    statusOutput, _ := cmd.Output()

    lines := strings.Split(string(statusOutput), "\n")
    modifiedCount := 0
    untrackedCount := 0

    for _, line := range lines {
        line = strings.TrimSpace(line)
        if line == "" {
            continue
        }
        if strings.HasPrefix(line, "??") {
            untrackedCount++
        } else {
            modifiedCount++
        }
    }

    info.ModifiedFiles = modifiedCount
    info.UntrackedFiles = untrackedCount

    if modifiedCount > 0 || untrackedCount > 0 {
        info.Status = "dirty"
    } else {
        info.Status = "clean"
    }

    // Check if ahead/behind remote
    cmd = exec.Command("git", "status", "-sb")
    cmd.Dir = repoPath
    aheadOutput, _ := cmd.Output()

    aheadRe := regexp.MustEach(`\[ahead (\d+)\]`)
    behindRe := regexp.MustEach(`behind (\d+)\]`)

    aheadMatch := aheadRe.FindStringSubmatch(string(aheadOutput))
    behindMatch := behindRe.FindStringSubmatch(string(aheadOutput))

    if len(aheadMatch) >= 2 {
        info.CommitsAhead, _ = strconv.Atoi(aheadMatch[1])
        info.Status = "ahead"
    }
    if len(behindMatch) >= 2 {
        info.CommitsBehind, _ = strconv.Atoi(behindMatch[1])
        info.Status = "behind"
    }

    return info
}

func (m *GitRepositoryMonitor) processRepoStatus(info *RepoInfo) {
    lastInfo := m.repoState[info.Path]

    if lastInfo == nil {
        m.repoState[info.Path] = info
        if info.Status == "dirty" && m.config.SoundOnMerge {
            m.onUncommittedChanges(info)
        }
        return
    }

    // Check for status changes
    if info.Status != lastInfo.Status {
        if info.Status == "dirty" && lastInfo.Status == "clean" {
            if m.config.SoundOnMerge {
                m.onUncommittedChanges(info)
            }
        } else if info.Status == "clean" && lastInfo.Status == "dirty" {
            m.onChangesCommitted(info)
        }
    }

    // Check for new uncommitted changes
    if info.ModifiedFiles > lastInfo.ModifiedFiles {
        if m.config.SoundOnMerge && m.shouldAlert(info.Path+"dirty", 2*time.Minute) {
            m.onUncommittedChanges(info)
        }
    }

    // Check for ahead/behind changes
    if info.CommitsAhead > lastInfo.CommitsAhead {
        if m.config.SoundOnPush && m.shouldAlert(info.Path+"push", 5*time.Minute) {
            m.onPushReceived(info)
        }
    }

    m.repoState[info.Path] = info
}

func (m *GitRepositoryMonitor) onUncommittedChanges(info *RepoInfo) {
    sound := m.config.Sounds["merge"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *GitRepositoryMonitor) onChangesCommitted(info *RepoInfo) {
    sound := m.config.Sounds["push"]
    if sound != "" {
        m.player.Play(sound, 0.3)
    }
}

func (m *GitRepositoryMonitor) onPushReceived(info *RepoInfo) {
    sound := m.config.Sounds["push"]
    if sound != "" {
        m.player.Play(sound, 0.4)
    }
}

func (m *GitRepositoryMonitor) shouldAlert(key string, interval time.Duration) bool {
    lastAlert := m.lastEventTime[key]
    if time.Since(lastAlert) < interval {
        return false
    }
    m.lastEventTime[key] = time.Now()
    return true
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| git | System Tool | Free | Version control system |

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
| macOS | Supported | Uses git CLI |
| Linux | Supported | Uses git CLI |
