---
title: "Nix Tricks"
date: 2024-04-08T16:03:11+07:00
draft: false
---

# Nix Tricks

A collection of tricks with nix

## review PR on any github project
The project must have a flake.nix for this to work

Template:
```command
nix flake check github:{user}/{repo}/pull/{PR_ID}/merge
```
Example:
```command
nix flake check github:nix-community/dream2nix/pull/924/merge
```
