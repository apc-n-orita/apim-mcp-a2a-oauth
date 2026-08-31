# Hands-On Flow

This directory is an **advanced edition** hands-on, built as a continuation of [apim-mcp-oauth](https://github.com/apc-n-orita/apim-mcp-oauth). On top of the same shared APIM instance, it layers configuration examples for both MCP (Model Context Protocol) and A2A (Agent2Agent protocol).

It assumes apim-mcp-oauth's base OAuth setup (shared APIM, shared Entra ID app, oauth-api, etc.) is already deployed.

## Contents

- **[mcp](mcp/README.md)** — exposing and calling MCP servers (foundry iq mcp / toolbox) through APIM
- **[a2a](a2a/README.md)** — calling a Foundry prompt agent over the A2A protocol through APIM (carried over as-is from the [root README](../README.md))
