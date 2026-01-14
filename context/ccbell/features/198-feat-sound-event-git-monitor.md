# Feature: Sound Event Git Monitor

Play sounds for git repository events.

## Summary

Play sounds when git operations complete or have specific outcomes.

## Motivation

- Build completion
- CI/CD feedback
- Repository monitoring

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Medium |
| **Complexity** | Low |
| **Estimated Effort** | 1-2 days |

---

## Technical Feasibility

### Git Events

| Event | Description | Example |
|-------|-------------|---------|
| Clone Complete | Repository cloned | Clone done |
| Pull Complete | Changes fetched | Pull done |
| Push Complete | Changes pushed | Push done |
| Merge Complete | Merge finished | Merge done |
| Build Success | Build succeeded | Tests passed |
| Build Failed | Build failed | Tests failed |

### Configuration

```go
type GitMonitorConfig struct {
    Enabled       bool              `json:"enabled"`
    WatchRepos    []*RepoWatch     `json:"watch_repos"`
    GlobalSounds  map[string]string `json:"global_sounds"`
}

type RepoWatch struct {
    Path         string  `json:"path"` // Repository path
    Branch       string  `json:"branch,omitempty"` // Specific branch
    Sounds       map[string]string `json:"sounds"`
    Enabled      bool    `json:"enabled"`
}

type GitEvent struct {
    Repo        string
    EventType   string
    Branch      string
    Commit      string
    Status      string // "success", "failed"
    Timestamp   time.Time
}
```

### Commands

```bash
/ccbell:git status                  # Show git status
/ccbell:git add /path/to/repo       # Watch repository
/ccbell:git add /path/to/repo --branch main
/ccbell:git sound clone <sound>
/ccbell:git sound pull <sound>
/ccbell:git sound push <sound>
/ccbell:git sound build_success <sound>
/ccbell:git sound build_failed <sound>
/ccbell:git remove /path/to/repo
/ccbell:git test                    # Test git sounds
```

### Output

```
$ ccbell:git status

=== Sound Event Git Monitor ===

Status: Enabled

Watched Repositories: 2

[1] /Users/user/project
    Branch: main
    Status: Clean
    Last Commit: 2 hours ago
    Sounds: [Clone, Pull, Push, Build Success, Build Failed]
    [Edit] [Remove]

[2] /Users/user/work
    Branch: develop
    Status: 3 uncommitted changes
    Last Commit: 1 day ago
    Sounds: [Pull, Push]
    [Edit] [Remove]

Recent Events:
  [1] project: Pull complete (3 min ago)
  [2] project: Build success (1 hour ago)
  [3] work: Changes detected (2 hours ago)

[Configure] [Add] [Test All]
```

---

## Audio Player Compatibility

Git monitoring doesn't play sounds:
- Monitoring feature
- No player changes required

---

## Implementation

### Git Monitor

```go
type GitMonitor struct {
    config   *GitMonitorConfig
    player   *audio.Player
    running  bool
    stopCh   chan struct{}
    lastStates map[string]*RepoState
}

type RepoState struct {
    Branch       string
    Commit       string
    Uncommitted  int
    LastCheck    time.Time
}

func (m *GitMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastStates = make(map[string]*RepoState)
    go m.monitor()
}

func (m *GitMonitor) monitor() {
    ticker := time.NewTicker(30 * time.Second)
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
    for _, repo := range m.config.WatchRepos {
        if !repo.Enabled {
            continue
        }

        state := m.getRepoState(repo.Path)
        m.evaluateRepo(repo, state)
    }
}

func (m *GitMonitor) getRepoState(repoPath string) *RepoState {
    state := &RepoState{
        LastCheck: time.Now(),
    }

    // Get current branch
    cmd := exec.Command("git", "rev-parse", "--abbrev-ref", "HEAD")
    cmd.Dir = repoPath
    if output, err := cmd.Output(); err == nil {
        state.Branch = strings.TrimSpace(string(output))
    }

    // Get current commit
    cmd = exec.Command("git", "rev-parse", "HEAD")
    if output, err := cmd.Output(); err == nil {
        state.Commit = strings.TrimSpace(string(output))[:7]
    }

    // Count uncommitted changes
    cmd = exec.Command("git", "status", "--porcelain")
    cmd.Dir = repoPath
    if output, err := cmd.Output(); err == nil {
        lines := strings.Split(string(output), "\n")
        for _, line := range lines {
            if strings.TrimSpace(line) != "" {
                state.Uncommitted++
            }
        }
    }

    return state
}

func (m *GitMonitor) evaluateRepo(repo *RepoWatch, state *RepoState) {
    lastState := m.lastStates[repo.Path]

    // Check for new uncommitted changes
    if lastState != nil && state.Uncommitted > 0 && lastState.Uncommitted == 0 {
        m.playGitEvent(repo, "changes", repo.Sounds["changes"])
    }

    // Check for clean state
    if lastState != nil && state.Uncommitted == 0 && lastState.Uncommitted > 0 {
        m.playGitEvent(repo, "clean", repo.Sounds["clean"])
    }

    // Check for branch change
    if lastState != nil && state.Branch != lastState.Branch {
        m.playGitEvent(repo, "branch_change", repo.Sounds["branch_change"])
    }

    m.lastStates[repo.Path] = state
}

// Alternative: Use git hooks for immediate feedback
func (m *GitMonitor) installHooks(repoPath string) error {
    // Create post-merge hook
    hookContent := `#!/bin/bash
ccbell git --event merge_complete --repo "` + repoPath + `"
`
    hookPath := filepath.Join(repoPath, ".git", "hooks", "post-merge")
    return os.WriteFile(hookPath, []byte(hookContent), 0755)
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| git | System Tool | Free | Git operations |

---

## References

### ccbell Implementation Research

- [Player implementation](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go) - Sound playback
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Event handling
- [Config structure](https://github.com/mpolatcan/ccbell/blob/main/internal/config/config.go) - Event config

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Uses git CLI |
| Linux | ✅ Supported | Uses git CLI |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
