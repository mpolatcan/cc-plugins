# Feature: Sound Event Workflows

Workflow definitions for complex event handling.

## Summary

Define multi-step workflows for events.

## Motivation

- Complex workflows
- Multi-step processes
- Orchestrated actions

---

## Priority & Complexity

| Attribute | Value |
|-----------|-------|
| **Priority** | Low |
| **Complexity** | Medium |
| **Estimated Effort** | 4-5 days |

---

## Technical Feasibility

### Workflow Components

| Component | Description | Example |
|-----------|-------------|---------|
| Steps | Ordered steps | step1 -> step2 |
| Parallel | Parallel execution | step1 & step2 |
| Branches | Conditional branches | if X then A else B |
| Loops | Repeat steps | repeat 3x |

### Configuration

```go
type WorkflowConfig struct {
    Enabled     bool              `json:"enabled"`
    Workflows   map[string]*Workflow `json:"workflows"`
}

type Workflow struct {
    ID          string   `json:"id"`
    Name        string   `json:"name"`
    Description string   `json:"description"`
    Trigger     WorkflowTrigger `json:"trigger"`
    Steps       []WorkflowStep `json:"steps"`
    Parallel    bool     `json:"parallel"` // run steps in parallel
    Timeout     int      `json:"timeout_ms"` // max duration
    Enabled     bool     `json:"enabled"`
}

type WorkflowTrigger struct {
    EventType   string `json:"event_type"`
    Condition   string `json:"condition,omitempty"` // optional
}

type WorkflowStep struct {
    ID          string `json:"id"`
    Name        string `json:"name"`
    Type        string `json:"type"` // "play", "wait", "condition", "branch", "loop"
    Config      map[string]string `json:"config"`
    Next        string `json:"next"` // next step ID
    BranchTrue  string `json:"branch_true,omitempty"` // step ID for true
    BranchFalse string `json:"branch_false,omitempty"` // step ID for false
    ParallelWith []string `json:"parallel_with,omitempty"` // parallel steps
}
```

### Commands

```bash
/ccbell:workflow list               # List workflows
/ccbell:workflow create "Alert Flow" # Create workflow
/ccbell:workflow add step play stop # Add play step
/ccbell:workflow add step wait 500  # Add wait step
/ccbell:workflow add step condition "volume>0.5"
/ccbell:workflow trigger stop       # Trigger workflow
/ccbell:workflow enable <id>        # Enable workflow
/ccbell:workflow delete <id>        # Remove workflow
/ccbell:workflow export <id>        # Export workflow
```

### Output

```
$ ccbell:workflow list

=== Sound Event Workflows ===

Status: Enabled
Workflows: 2

[1] Alert Flow
    Trigger: stop event
    Steps: 5
    Parallel: No
    Enabled: Yes
    [Run] [Edit] [Export] [Delete]

    Steps:
      [1] Play stop sound
      [2] Wait 500ms
      [3] Check volume (>0.5?)
      [4] If true: Play soft sound
      [5] If false: Log event

    [Run] [Edit] [Export] [Delete]

[2] Priority Alert
    Trigger: permission_prompt
    Steps: 3
    Parallel: Yes
    Enabled: Yes
    [Run] [Edit] [Export] [Delete]

[Create]
```

---

## Audio Player Compatibility

Workflows use existing audio player:
- Executes `player.Play()` in workflow steps
- Same format support
- No player changes required

---

## Implementation

### Workflow Execution

```go
type WorkflowEngine struct {
    config  *WorkflowConfig
    player  *audio.Player
}

func (e *WorkflowEngine) Execute(workflowID string, eventType string, cfg *EventConfig) error {
    workflow, ok := e.config.Workflows[workflowID]
    if !ok {
        return fmt.Errorf("workflow not found: %s", workflowID)
    }

    if workflow.Trigger.EventType != eventType {
        return nil // Not triggered
    }

    ctx, cancel := context.WithTimeout(context.Background(), time.Duration(workflow.Timeout)*time.Millisecond)
    defer cancel()

    return e.executeStep(workflow, workflow.Steps[0], ctx, cfg)
}

func (e *WorkflowEngine) executeStep(workflow *Workflow, step WorkflowStep, ctx context.Context, cfg *EventConfig) error {
    if ctx.Err() != nil {
        return ctx.Err()
    }

    switch step.Type {
    case "play":
        sound := step.Config["sound"]
        vol, _ := strconv.ParseFloat(step.Config["volume"], 64)
        return e.player.Play(sound, vol)

    case "wait":
        ms, _ := strconv.Atoi(step.Config["duration"])
        time.Sleep(time.Duration(ms) * time.Millisecond)

    case "condition":
        // Evaluate condition
        result := e.evaluateCondition(step.Config["condition"], cfg)
        if result {
            if step.BranchTrue != "" {
                return e.executeStepByID(workflow, step.BranchTrue, ctx, cfg)
            }
        } else {
            if step.BranchFalse != "" {
                return e.executeStepByID(workflow, step.BranchFalse, ctx, cfg)
            }
        }
    }

    // Execute next step
    if step.Next != "" {
        return e.executeStepByID(workflow, step.Next, ctx, cfg)
    }

    return nil
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

- [Player.Play](https://github.com/mpolatcan/ccbell/blob/main/internal/audio/player.go#L93-113) - Workflow playback
- [Main flow](https://github.com/mpolatcan/ccbell/blob/main/cmd/ccbell/main.go) - Workflow triggering

---

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| macOS | ✅ Supported | Pure Go |
| Linux | ✅ Supported | Pure Go |
| Windows | ❌ Not Supported | ccbell only supports macOS/Linux |
