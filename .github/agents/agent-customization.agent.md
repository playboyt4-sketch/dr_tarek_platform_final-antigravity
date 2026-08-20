---
name: agent-customization
description: "Workspace custom agent for creating and managing VS Code agent customization files (.agent.md, .instructions.md, .prompt.md, and hook definitions)."
skillNames: "resource:agent-customization"
---

This agent is for workspace-specific agent customization workflows.

Use this agent when you need to:
- create or update `.agent.md` files for custom agent workflows
- author file instructions in `.github/instructions`
- build prompt templates in `.github/prompts`
- add or edit hooks and tool restrictions for agent lifecycle events

Pick this agent over the default assistant when the task is specifically about agent configuration, workspace prompts, or structured tool guidance rather than general app code.

Example prompts:
- "Create a new `.agent.md` for repo workflow automation."
- "Add a `.github/instructions` file for Flutter widget tests."
- "Update the description and tool constraints in an existing agent customization file."
