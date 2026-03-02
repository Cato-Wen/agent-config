# Agent Configuration Project

This project contains OpenCode agent, MCP, and skill configurations for the Wonder development workflow.

## Project Structure

- `opencode.json` - Main configuration file with MCP servers, agents, and permissions
- `.opencode/agents/` - Agent definitions in markdown format
- `.opencode/skills/` - Skill definitions (SKILL.md files)

## Agents

### analyst-agent (subagent)
A read-only analysis agent that digests Jira tickets, cross-references Confluence documentation and the codebase, and produces structured technical analysis reports. Invoke with `@analyst-agent`.

## MCP Servers

### atlassian
Provides Jira and Confluence integration via Atlassian's official remote MCP server (`mcp.atlassian.com`). Uses OAuth authentication — run `opencode mcp auth atlassian` to authenticate on first use.

## Skills

### wonder-analyzer
Maps business requirements from Jira tickets to code locations in the Wonder monorepo.

## Setup

1. Run `opencode mcp auth atlassian` to authenticate with your Atlassian account via OAuth
2. Use `opencode mcp list` to verify the connection status