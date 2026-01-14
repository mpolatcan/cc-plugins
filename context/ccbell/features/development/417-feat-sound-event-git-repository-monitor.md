# Feature: Sound Event Git Repository Monitor

Play sounds for git commits, pushes, pull requests, and branch changes.

## Summary

Monitor git repositories for commits, pushes, branch changes, and merge events, playing sounds for git operations.

## Motivation

- Commit awareness
- Push notification
- Branch change tracking
- CI/CD feedback
- Development activity

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1 day |

---

## Technical Feasibility

### Git Repository Events

| Event | Description | Example |
|-------|-------------|---------|
| New Commit | New commit added | abc1234 |
| Commit Pushed | Changes pushed | origin main |
| Branch Created | New branch | feature/new |
| Branch Deleted | Branch removed | old-branch |
| Tag Created | Annotated tag | v1.0.0 |
| Merge Conflict | Conflict detected | auto-merge failed |
| Pull Request | PR opened/updated | #42 |

### Configuration

```go
type GitRepositoryMonitorConfig struct {
    Enabled           bool              `json:"enabled"`
    WatchRepos        []string          `json:"watch_repos"` // "/path/to/repo"
    WatchBranches     []string          `json:"watch_branches"` // "main", "develop", "*"
    SoundOnCommit     bool              `json:"sound_on_commit"`
    SoundOnPush       bool              `json:"sound_on_push"`
    SoundOnBranch     bool              `json:"sound_on_branch"`
    SoundOnMerge      bool              `json:"sound_on_merge"`
    Sounds            map[string]string `json:"sounds"`
    PollInterval      int               `json:"poll_interval_sec"` // 60 default
}
```

### Commands

```bash
/ccbell:git status                   # Show git monitor status
/ccbell:git add ~/project            # Add repo to watch
/ccbell:git remove ~/project
/ccbell:git sound commit <sound>
/ccbell:git sound push <sound>
/ccbell:git test                     # Test git sounds
```

### Output

```
$ ccbell:git status

=== Sound Event Git Repository Monitor ===

Status: Enabled
Commit Sounds: Yes
Push Sounds: Yes
Branch Sounds: Yes

Watched Repositories: 2

Repository Status:

[1] ~/project (main)
    Status: ACTIVE
    Current Branch: main
    Remote: origin
    Uncommitted: 3
    Last Commit: 2 hours ago
    Sound: bundled:git-main

[2] ~/project (feature/auth)
    Status: ACTIVE
    Current Branch: feature/auth
    Remote: origin
    Uncommitted: 0
    Last Commit: 5 min ago
    Sound: bundled:git-feature

[3] ~/work/api (develop)
    Status: ACTIVE
    Current Branch: develop
    Remote: origin
    Uncommitted: 5
    Last Push: 1 hour ago
    Sound: bundled:git-work

Recent Git Events:

[1] ~/project: New Commit (5 min ago)
       abc1234: Add user authentication
       Author: John Doe
       Sound: bundled:git-commit

[2] ~/work/api: Branch Created (30 min ago)
       feature/graphql-api
       Sound: bundled:git-branch

[3] ~/project: Changes Pushed (2 hours ago)
       3 commits to main
       Sound: bundled:git-push

Repository Statistics:
  Total Repos: 3
  Commits Today: 12
  Pushes Today: 5
  Branch Changes: 3

Sound Settings:
  Commit: bundled:git-commit
  Push: bundled:git-push
  Branch: bundled:git-branch
  Merge: bundled:git-merge

[Configure] [Add Repo] [Test All]
```

---

## Audio Player Compatibility

Git monitoring doesn't play sounds directly:
- Monitoring feature using git command
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
    Path           string
    CurrentBranch  string
    RemoteName     string
    RemoteURL      string
    LastCommit     string
    LastCommitHash string
    LastCommitTime time.Time
    Uncommitted    int
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
        expandedPath := m.expandPath(repoPath)

        info := m.getRepoInfo(expandedPath)
        if info != nil {
            m.processRepoStatus(expandedPath, info)
        }
    }
}

func (m *GitRepositoryMonitor) getRepoInfo(repoPath string) *RepoInfo {
    // Check if directory is a git repo
    if !m.isGitRepo(repoPath) {
        return nil
    }

    info := &RepoInfo{
        Path: repoPath,
    }

    // Get current branch
    cmd := exec.Command("git", "rev-parse", "--abbrev-ref", "HEAD")
    cmd.Dir = repoPath
    output, _ := cmd.Output()
    info.CurrentBranch = strings.TrimSpace(string(output))

    // Get remote name
    cmd = exec.Command("git", "remote")
    cmd.Dir = repoPath
    output, _ = cmd.Output()
    remotes := strings.Split(string(output), "\n")
    if len(remotes) > 0 && remotes[0] != "" {
        info.RemoteName = strings.TrimSpace(remotes[0])
    }

    // Get last commit
    cmd = exec.Command("git", "log", "-1", "--pretty=format:%H%n%s")
    cmd.Dir = repoPath
    output, _ = cmd.Output()
    lines := strings.Split(string(output), "\n")
    if len(lines) >= 2 {
        info.LastCommitHash = lines[0]
        info.LastCommit = lines[1]
    }

    // Get last commit time
    cmd = exec.Command("git", "log", "-1", "--format=%ai")
    cmd.Dir = repoPath
    output, _ = cmd.Output()
    ts := strings.TrimSpace(string(output))
    info.LastCommitTime, _ = time.Parse("2006-01-02 15:04:05 -0700", ts)

    // Get uncommitted changes
    cmd = exec.Command("git", "status", "--porcelain")
    cmd.Dir = repoPath
    output, _ = cmd.Output()
    lines = strings.Split(string(output), "\n")
    uncommitted := 0
    for _, line := range lines {
        if strings.TrimSpace(line) != "" {
            uncommitted++
        }
    }
    info.Uncommitted = uncommitted

    return info
}

func (m *GitRepositoryMonitor) isGitRepo(path string) bool {
    gitDir := filepath.Join(path, ".git")
    _, err := os.Stat(gitDir)
    return err == nil
}

func (m *GitRepositoryMonitor) processRepoStatus(repoPath string, info *RepoInfo) {
    lastInfo := m.repoState[repoPath]

    if lastInfo == nil {
        m.repoState[repoPath] = info
        return
    }

    // Check for new commits
    if info.LastCommitHash != lastInfo.LastCommitHash {
        if m.config.SoundOnCommit {
            m.onNewCommit(info)
        }
    }

    // Check for branch changes
    if info.CurrentBranch != lastInfo.CurrentBranch {
        if m.config.SoundOnBranch {
            m.onBranchChanged(info, lastInfo)
        }
    }

    // Check for changes in uncommitted count
    if info.Uncommitted > 0 && lastInfo.Uncommitted == 0 {
        // Uncommitted changes appeared
    }

    m.repoState[repoPath] = info
}

func (m *GitRepositoryMonitor) shouldWatchBranch(branch string) bool {
    if len(m.config.WatchBranches) == 0 {
        return true
    }

    for _, b := range m.config.WatchBranches {
        if b == "*" || branch == b {
            return true
        }
    }

    return false
}

func (m *GitRepositoryMonitor) onNewCommit(info *RepoInfo) {
    if !m.shouldWatchBranch(info.CurrentBranch) {
        return
    }

    key := fmt.Sprintf("commit:%s:%s", info.Path, info.LastCommitHash)
    if m.shouldAlert(key, 30*time.Second) {
        sound := m.config.Sounds["commit"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *GitRepositoryMonitor) onBranchChanged(info, lastInfo *RepoInfo) {
    key := fmt.Sprintf("branch:%s:%s", info.Path, info.CurrentBranch)
    if m.shouldAlert(key, 1*time.Minute) {
        sound := m.config.Sounds["branch"]
        if sound != "" {
            m.player.Play(sound, 0.4)
        }
    }
}

func (m *GitRepositoryMonitor) expandPath(path string) string {
    if strings.HasPrefix(path, "~") {
        home, _ := os.UserHomeDir()
        path = filepath.Join(home, path[2:])
    }
    return path
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
