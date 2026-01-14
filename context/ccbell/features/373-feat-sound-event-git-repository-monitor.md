# Feature: Sound Event Git Repository Monitor

Play sounds for git repository events, branch changes, and commit activities.

## Summary

Monitor git repositories for commits, branch changes, and merge events, playing sounds for git events.

## Motivation

- Repository awareness
- Deployment tracking
- Commit notifications
- Branch change alerts
- CI/CD feedback

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
| New Commit | New commit pushed | git push |
| Branch Created | New branch created | feature/x |
| Branch Deleted | Branch deleted | old branch |
| Tag Created | New tag created | v1.0.0 |
| Merge Completed | Merge finished | branch merged |
| Push Failed | Push rejected | denied |

### Configuration

```go
type GitRepositoryMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    Repositories      []GitRepoConfig   `json:"repositories"`
    SoundOnCommit     bool              `json:"sound_on_commit"`
    SoundOnBranch     bool              `json:"sound_on_branch"]
    SoundOnTag        bool              `json:"sound_on_tag"]
    SoundOnMerge      bool              `json:"sound_on_merge"]
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
}

type GitRepoConfig struct {
    Name     string `json:"name"` // "myapp"
    Path     string `json:"path"` // "/path/to/repo"
    Remote   string `json:"remote"` // "origin"
    Branch   string `json:"branch"` // "main"
}

type GitRepositoryEvent struct {
    Repository  string
    Type        string // "commit", "branch", "tag", "merge"
    Ref         string // branch/tag name
    Author      string
    Message     string
    SHA         string
    EventType   string // "commit", "create_branch", "delete_branch", "tag", "merge"
}
```

### Commands

```bash
/ccbell:git status                    # Show git status
/ccbell:git add /path/to/repo         # Add repository to watch
/ccbell:git remove /path/to/repo
/ccbell:git sound commit <sound>
/ccbell:git sound branch <sound>
/ccbell:git test                      # Test git sounds
```

### Output

```
$ ccbell:git status

=== Sound Event Git Repository Monitor ===

Status: Enabled
Commit Sounds: Yes
Branch Sounds: Yes
Tag Sounds: Yes

Monitored Repositories: 2

[1] myapp (/home/repos/myapp)
    Branch: main
    Latest: 3 minutes ago
    Author: John Doe
    Commit: abc1234 Fix authentication bug
    Sound: bundled:git-myapp

[2] api (/home/repos/api)
    Branch: feature/new-endpoint
    Latest: 1 hour ago
    Author: Jane Smith
    Commit: def5678 Add new API endpoint
    Sound: bundled:git-api

Recent Events:
  [1] myapp: New Commit (3 min ago)
       Author: John Doe
       Message: Fix authentication bug
  [2] myapp: Branch Created (1 hour ago)
       Branch: hotfix/critical-fix
  [3] api: Tag Created (2 hours ago)
       Tag: v2.1.0

Repository Statistics:
  Total Commits Today: 15
  New Branches: 3
  New Tags: 1

Sound Settings:
  Commit: bundled:git-commit
  Branch: bundled:git-branch
  Tag: bundled:git-tag
  Merge: bundled:git-merge

[Configure] [Add Repository] [Test All]
```

---

## Audio Player Compatibility

Git monitoring doesn't play sounds directly:
- Monitoring feature using git commands
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Git Repository Monitor

```go
type GitRepositoryMonitor struct {
    config          *GitRepositoryMonitorConfig
    player          *audio.Player
    running         bool
    stopCh          chan struct{}
    repoState       map[string]*RepoInfo
    lastEventTime   map[string]time.Time
}

type RepoInfo struct {
    Name       string
    Path       string
    Branch     string
    HEAD       string
    LastCommit string
    LastAuthor string
    LastTime   time.Time
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
    for _, repo := range m.config.Repositories {
        m.checkRepository(&repo)
    }
}

func (m *GitRepositoryMonitor) checkRepoState() {
    for _, repo := range m.config.Repositories {
        m.checkRepository(&repo)
    }
}

func (m *GitRepositoryMonitor) checkRepository(config *GitRepoConfig) {
    // Get current HEAD
    cmd := exec.Command("git", "-C", config.Path, "rev-parse", "HEAD")
    output, err := cmd.Output()
    if err != nil {
        return
    }

    currentSHA := strings.TrimSpace(string(output))

    info := &RepoInfo{
        Name:     config.Name,
        Path:     config.Path,
        HEAD:     currentSHA,
        LastTime: time.Now(),
    }

    // Get current branch
    cmd = exec.Command("git", "-C", config.Path, "rev-parse", "--abbrev-ref", "HEAD")
    branchOutput, _ := cmd.Output()
    info.Branch = strings.TrimSpace(string(branchOutput))

    lastInfo := m.repoState[config.Name]
    if lastInfo == nil {
        m.repoState[config.Name] = info
        return
    }

    // Check for new commits
    if currentSHA != lastInfo.HEAD {
        m.onNewCommit(config, info, lastInfo)
    }

    // Check for branch changes
    if info.Branch != lastInfo.Branch {
        m.onBranchChanged(config, info, lastInfo)
    }

    m.repoState[config.Name] = info
}

func (m *GitRepositoryMonitor) onNewCommit(config *GitRepoConfig, info *RepoInfo, lastInfo *RepoInfo) {
    if !m.config.SoundOnCommit {
        return
    }

    // Get commit details
    cmd := exec.Command("git", "-C", config.Path, "log", "-1", "--format=%an|%s", info.HEAD)
    output, err := cmd.Output()
    if err != nil {
        return
    }

    parts := strings.SplitN(string(output), "|", 2)
    author := parts[0]
    message := parts[1]

    key := fmt.Sprintf("commit:%s:%s", config.Name, info.HEAD[:7])
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["commit"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *GitRepositoryMonitor) onBranchChanged(config *GitRepoConfig, info *RepoInfo, lastInfo *RepoInfo) {
    if !m.config.SoundOnBranch {
        return
    }

    // Check if branch was deleted or created
    cmd := exec.Command("git", "-C", config.Path, "branch", "-a", "--contains", lastInfo.Branch)
    _, err := cmd.Output()

    isDeleted := err != nil

    key := fmt.Sprintf("branch:%s:%s->%s", config.Name, lastInfo.Branch, info.Branch)
    if m.shouldAlert(key, 5*time.Minute) {
        sound := m.config.Sounds["branch"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *GitRepositoryMonitor) onTagCreated(config *GitRepoConfig, tagName string, info *RepoInfo) {
    if !m.config.SoundOnTag {
        return
    }

    key := fmt.Sprintf("tag:%s:%s", config.Name, tagName)
    if m.shouldAlert(key, 30*time.Minute) {
        sound := m.config.Sounds["tag"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *GitRepositoryMonitor) onMergeCompleted(config *GitRepoConfig, info *RepoInfo) {
    if !m.config.SoundOnMerge {
        return
    }

    key := fmt.Sprintf("merge:%s", config.Name)
    if m.shouldAlert(key, 10*time.Minute) {
        sound := m.config.Sounds["merge"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
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
| git | System Tool | Free | Version control |

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
| macOS | Supported | Uses git |
| Linux | Supported | Uses git |
