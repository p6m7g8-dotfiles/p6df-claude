# P6's POSIX.2: p6df-claudecode

## Table of Contents

- [Badges](#badges)
- [Summary](#summary)
- [Contributing](#contributing)
- [Code of Conduct](#code-of-conduct)
- [Usage](#usage)
  - [Functions](#functions)
- [Hierarchy](#hierarchy)
- [Author](#author)

## Badges

[![License](https://img.shields.io/badge/License-Apache%202.0-yellowgreen.svg)](https://opensource.org/licenses/Apache-2.0)

## Summary

p6df module for Claude Code: aliases, prompt integration, profile switching,
MCP server setup, and Anthropic API key management.

## Contributing

- [How to Contribute](<https://github.com/p6m7g8-dotfiles/.github/blob/main/CONTRIBUTING.md>)

## Code of Conduct

- [Code of Conduct](<https://github.com/p6m7g8-dotfiles/.github/blob/main/CODE_OF_CONDUCT.md>)

## Usage

### Functions

#### p6df-claudecode

##### p6df-claudecode/init.zsh

- `p6df::modules::claudecode::aliases::init()`
- `p6df::modules::claudecode::deps()`
- `p6df::modules::claudecode::external::brew()`
- `p6df::modules::claudecode::init(_module, dir)`
  - Args:
    - _module
    - dir
- `p6df::modules::claudecode::mcp::env()`
- `p6df::modules::claudecode::profile::off()`
- `p6df::modules::claudecode::profile::on(profile, [token=])`
  - Args:
    - profile
    - OPTIONAL token - []
- `p6df::modules::claudecode::vscodes::config()`
- `str str = p6df::modules::claudecode::prompt::mod()`

## Hierarchy

```text
.
├── init.zsh
├── lib
├── README.md
└── share

3 directories, 2 files
```

## Author

Philip M. Gollucci <pgollucci@p6m7g8.com>
