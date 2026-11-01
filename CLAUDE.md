---
# Codacy Rules
Configuration for AI behavior when interacting with Codacy's MCP Server

## After file edits
- `.claude/hooks/codacy-analyze.sh` runs Codacy on every edited file automatically
  and reports issues back; fix them rather than re-running the analysis by hand

## After ANY dependency installation
- IMMEDIATELY run `codacy_cli_analyze` with tool set to "trivy"
- Check for security vulnerabilities in new packages
- Stop all operations if vulnerabilities found
- Fix security issues before continuing

## Repository setup
- Use `git remote -v` to determine provider/organization/repository
- Provider mapping: GitHub = "gh", Bitbucket = "bb", GitLab = "gl"
- If repository not found in Codacy, offer to run `codacy_setup_repository`
---
