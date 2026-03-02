---
name: wonder-analyzer
description: Analyze Jira requirements and locate relevant code in the Wonder monorepo. Maps business terms to code locations, identifies affected modules, and finds reusable patterns.
---

# Wonder Analyzer

Expert codebase analysis skill for the Wonder monorepo. Use this skill when starting a new development task with a Jira ticket ID (MD-XXXXX).

## Capabilities

- Fetch Jira ticket details and extract business context
- Map business concepts (dormant, 40-model, WSKU, ERP sync, hot hold, pack size, BOM, version, item type) to code locations
- Identify related code modules, existing implementations, and reusable patterns
- Search requirement docs, git history, and map business terms to code

## Analysis Strategy

1. **Extract Business Terms**: Parse the Jira ticket for domain-specific keywords and business concepts
2. **Code Search**: Use `grep` and `glob` to locate relevant source files matching business terms
3. **Module Identification**: Identify which services and modules are affected
4. **Pattern Discovery**: Find existing implementations of similar features that can be reused
5. **API Mapping**: Locate relevant API endpoints and data models

## Business Term Mappings

Common Wonder domain terms and their likely code locations:
- **MS Cards** (MS05-xx, MS06-xx, MS08-xx, MS13-xx, MS15-xx): Menu/master data services
- **WSKU**: Warehouse SKU management
- **BOM**: Bill of Materials / recipe management
- **ERP Sync**: Enterprise resource planning integration
- **Pack Size**: Packaging and quantity management

## Output

Provide a structured analysis of:
- Affected modules and file paths
- Relevant API endpoints
- Data models involved
- Existing patterns that can be reused
- Potential risks or complexity areas