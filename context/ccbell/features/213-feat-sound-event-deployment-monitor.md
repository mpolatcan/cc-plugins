# Feature: Sound Event Deployment Monitor

Play sounds for deployment process events.

## Summary

Monitor deployment processes (Docker, Kubernetes, Heroku, Vercel), playing sounds when deployments start, complete, or fail.

## Motivation

- Deployment awareness without watching CI/CD
- Production change alerts
- Rollback detection
- Environment updates

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 3-4 days |

---

## Technical Feasibility

### Deployment Events

| Event | Description | Example |
|-------|-------------|---------|
| Deployment Started | New deployment began | `kubectl apply` |
| Deployment Complete | Successfully deployed | New version running |
| Deployment Failed | Deployment errored | CrashLoopBackOff |
| Rollback Initiated | Rolled back to previous | Version reverted |
| Scaling Started | Pods scaling up/down | replicas changed |
| Health Check Failed | Liveness probe failed | Container unhealthy |

### Configuration

```go
type DeploymentMonitorConfig struct {
    Enabled       bool              `json:"enabled"`
    Environments  []*DeployEnv     `json:"environments"`
    Sounds        map[string]string `json:"sounds"`
}

type DeployEnv struct {
    Name       string  `json:"name"`
    Type       string  `json:"type"` // "kubernetes", "docker", "heroku", "vercel"
    Config     map[string]string `json:"config"` // API keys, URLs
    Sound      string  `json:"sound"`
    PollInterval int   `json:"poll_interval_sec"` // 60 default
}

type DeployStatus struct {
    Environment string
    Status      string // "deploying", "running", "failed", "rolled_back"
    Version     string
    Replicas    int
    Available   int
    Message     string
}
```

### Commands

```bash
/ccbell:deploy status             # Show deployment status
/ccbell:deploy add production --type kubernetes
/ccbell:deploy remove production
/ccbell:deploy sound started <sound>
/ccbell:deploy sound complete <sound>
/ccbell:deploy sound failed <sound>
/ccbell:deploy test               # Test deploy sounds
```

### Output

```
$ ccbell:deploy status

=== Sound Event Deployment Monitor ===

Status: Enabled

Monitored Environments: 2

[1] production
    Type: Kubernetes
    Status: RUNNING
    Version: v2.3.1
    Replicas: 3/3
    Available: 3
    Last Deploy: 2 hours ago
    Sound: bundled:stop
    [Edit] [Remove]

[2] staging
    Type: Kubernetes
    Status: DEPLOYING
    Version: v2.4.0-rc1
    Replicas: 1/3
    Available: 0
    Progress: 33%
    Sound: bundled:stop
    [Edit] [Remove]

Recent Events:
  [1] production: Deployment Complete (v2.3.1) (2 hours ago)
  [2] staging: Deployment Started (v2.4.0-rc1) (5 min ago)
  [3] production: Deployment Complete (v2.3.0) (1 day ago)

[Configure] [Add] [Test All]
```

---

## Audio Player Compatibility

Deployment monitoring doesn't play sounds directly:
- Monitoring feature using API clients and CLI tools
- No player changes required
- Uses existing audio player infrastructure

---

## Implementation

### Deployment Monitor

```go
type DeploymentMonitor struct {
    config     *DeploymentMonitorConfig
    player     *audio.Player
    running    bool
    stopCh     chan struct{}
    lastStatus map[string]*DeployStatus
}

func (m *DeploymentMonitor) Start() {
    m.running = true
    m.stopCh = make(chan struct{})
    m.lastStatus = make(map[string]*DeployStatus)
    go m.monitor()
}

func (m *DeploymentMonitor) monitor() {
    // Create ticker with minimum interval
    interval := 60 // default
    for _, env := range m.config.Environments {
        if env.PollInterval > interval {
            interval = env.PollInterval
        }
    }

    ticker := time.NewTicker(time.Duration(interval) * time.Second)
    defer ticker.Stop()

    for {
        select {
        case <-ticker.C:
            m.checkDeployments()
        case <-m.stopCh:
            return
        }
    }
}

func (m *DeploymentMonitor) checkDeployments() {
    for _, env := range m.config.Environments {
        status := m.getDeploymentStatus(env)
        if status != nil {
            m.evaluateStatus(env, status)
        }
    }
}

func (m *DeploymentMonitor) getDeploymentStatus(env *DeployEnv) *DeployStatus {
    status := &DeployStatus{
        Environment: env.Name,
    }

    switch env.Type {
    case "kubernetes":
        return m.getKubernetesStatus(env, status)
    case "docker":
        return m.getDockerStatus(env, status)
    case "heroku":
        return m.getHerokuStatus(env, status)
    case "vercel":
        return m.getVercelStatus(env, status)
    }

    return status
}

func (m *DeploymentMonitor) getKubernetesStatus(env *DeployEnv, status *DeployStatus) *DeployStatus {
    // Get deployment status via kubectl
    namespace := env.Config["namespace"]
    deployment := env.Config["deployment"]

    cmd := exec.Command("kubectl", "get", "deployment", deployment,
        "-n", namespace, "-o", "json")
    output, err := cmd.Output()
    if err != nil {
        status.Status = "unknown"
        return status
    }

    var deploy v1.Deployment
    if err := json.Unmarshal(output, &deploy); err != nil {
        status.Status = "unknown"
        return status
    }

    status.Replicas = int(*deploy.Spec.Replicas)
    status.Available = int(deploy.Status.AvailableReplicas)
    status.Version = deploy.Labels["version"]

    // Check if deploying
    if status.Available < status.Replicas {
        status.Status = "deploying"
    } else if deploy.Status.ReadyReplicas == nil || *deploy.Status.ReadyReplicas == 0 {
        status.Status = "failed"
    } else {
        status.Status = "running"
    }

    return status
}

func (m *DeploymentMonitor) getDockerStatus(env *DeployEnv, status *DeployStatus) *DeployStatus {
    // Check docker-compose or docker service status
    project := env.Config["project"]

    cmd := exec.Command("docker-compose", "ps", project)
    output, err := cmd.Output()
    if err != nil {
        status.Status = "unknown"
        return status
    }

    lines := strings.Split(string(output), "\n")
    var running, total int

    for _, line := range lines {
        if strings.Contains(line, "Up") {
            running++
        }
        if strings.Contains(line, "Name") || strings.HasPrefix(line, project) {
            total++
        }
    }

    status.Replicas = total
    status.Available = running

    if running == 0 {
        status.Status = "failed"
    } else if running < total {
        status.Status = "deploying"
    } else {
        status.Status = "running"
    }

    return status
}

func (m *DeploymentMonitor) getHerokuStatus(env *DeployEnv, status *DeployStatus) *DeployStatus {
    // Use Heroku CLI to check formation
    app := env.Config["app"]

    cmd := exec.Command("heroku", "ps", "-a", app)
    output, err := cmd.Output()
    if err != nil {
        status.Status = "unknown"
        return status
    }

    lines := strings.Split(string(output), "\n")
    var running int

    for _, line := range lines {
        if strings.Contains(line, "up") {
            running++
        }
    }

    status.Replicas = len(lines) - 1
    status.Available = running

    if running == 0 {
        status.Status = "failed"
    } else {
        status.Status = "running"
    }

    return status
}

func (m *DeploymentMonitor) getVercelStatus(env *DeployEnv, status *DeployStatus) *DeployEnv {
    // Vercel uses API - requires token
    token := env.Config["token"]
    project := env.Config["project"]

    client := &http.Client{}
    req, _ := http.NewRequest("GET",
        fmt.Sprintf("https://api.vercel.com/v6/deployments?project=%s&limit=1", project),
        nil)
    req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", token))

    resp, err := client.Do(req)
    if err != nil {
        status.Status = "unknown"
        return status
    }
    defer resp.Body.Close()

    var result struct {
        Deployments []struct {
            State string `json:"state"`
            URL   string `json:"url"`
        } `json:"deployments"`
    }

    if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
        status.Status = "unknown"
        return status
    }

    if len(result.Deployments) > 0 {
        status.Status = result.Deployments[0].State
        status.Version = result.Deployments[0].URL
    }

    return status
}

func (m *DeploymentMonitor) evaluateStatus(env *DeployEnv, status *DeployStatus) {
    lastStatus := m.lastStatus[env.Name]
    m.lastStatus[env.Name] = status

    if lastStatus == nil {
        return
    }

    // Check status changes
    if lastStatus.Status != status.Status {
        switch status.Status {
        case "deploying":
            m.playSound(env, "started")
        case "READY", "running":
            m.playSound(env, "complete")
        case "error", "failed", "FATAL":
            m.playSound(env, "failed")
        case "canceled":
            m.playSound(env, "canceled")
        }
    }

    // Check version changes
    if lastStatus.Version != status.Version && status.Status == "running" {
        m.playSound(env, "version_changed")
    }
}

func (m *DeploymentMonitor) playSound(env *DeployEnv, event string) {
    sound := env.Sound
    if sound == "" {
        sound = m.config.Sounds[event]
    }
    if sound != "" {
        m.player.Play(sound, 0.5)
    }
}
```

---

## External Dependencies

| Dependency | Type | Cost | Notes |
|------------|------|------|-------|
| kubectl | CLI Tool | Free | Kubernetes management |
| docker-compose | CLI Tool | Free | Docker orchestration |
| heroku | CLI Tool | Free | Heroku management |
| http | Go Stdlib | Free | Vercel API calls |

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
| macOS | Supported | Uses CLI tools and API |
| Linux | Supported | Uses CLI tools and API |
| Windows | Not Supported | ccbell only supports macOS/Linux |
