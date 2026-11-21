---
task: T1                 # file name is T1.md
issue: "#123"            # the issue of the task in tasks.md
status: in-progress      # todo -> in-progress (the agent takes the task) -> done (after the review phase)
agent: terraform-engineer
pr: none                 # "#N" or the pull request URL; required when done
---

# Progress of T1

The agent that takes the task sets the issue to In progress and writes this file before its first commit.
After the review phase passes, the orchestrator sets `done` here and the issue to Done, and records the pull request.
