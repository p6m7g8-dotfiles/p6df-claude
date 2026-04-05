# P6's POSIX.2: p6df-claude

## Table of Contents

- [Badges](#badges)
- [Summary](#summary)
- [Contributing](#contributing)
- [Code of Conduct](#code-of-conduct)
- [Usage](#usage)
  - [Aliases](#aliases)
  - [Functions](#functions)
- [Hierarchy](#hierarchy)
- [Author](#author)

## Badges

[![License](https://img.shields.io/badge/License-Apache%202.0-yellowgreen.svg)](https://opensource.org/licenses/Apache-2.0)

## Summary

TODO: Add a short summary of this module.

## Contributing

- [How to Contribute](<https://github.com/p6m7g8-dotfiles/.github/blob/main/CONTRIBUTING.md>)

## Code of Conduct

- [Code of Conduct](<https://github.com/p6m7g8-dotfiles/.github/blob/main/CODE_OF_CONDUCT.md>)

## Usage

### Aliases

- `cl` -> `claude`
- `clacl` -> `p6df::modules::claude::sandbox::select arkestro; p6df::modules::claude::sandbox::runner`
- `clcat` -> `claude --print`
- `cld` -> `CLAUDE_DEBUG=1 claude`
- `clenv` -> `env | p6_filter_row_select_icase `
- `clh` -> `claude --help`
- `clii` -> `claude --interactive`
- `clp6cl` -> `p6df::modules::claude::sandbox::select p6;      p6df::modules::claude::sandbox::runner`
- `clsf` -> `claude --resume --fork-session`
- `clsn` -> `claude --no-session-persistence`
- `clv` -> `claude --version`
- `clvv` -> `CLAUDE_DEBUG=1 CLAUDE_VERBOSE=1 claude`
- `clx` -> `xargs -I{} claude --print <<< `
- `p6_claude` -> `p6df::modules::claude::sandbox::runner`

### Functions

#### p6df-claude

##### p6df-claude/init.zsh

- `p6df::modules::claude::aliases::init(_module, _dir)`
  - Args:
    - _module
    - _dir
- `p6df::modules::claude::deps()`
- `p6df::modules::claude::env::init(_module, _dir)`
  - Args:
    - _module
    - _dir
- `p6df::modules::claude::external::brews()`
- `p6df::modules::claude::langs()`
- `p6df::modules::claude::path::init(_module, _dir)`
  - Args:
    - _module
    - _dir
- `p6df::modules::claude::vscodes::config()`
- `words claude = p6df::modules::claude::profile::mod()`

#### p6df-claude/lib

##### p6df-claude/lib/sandbox.sh

- `p6df::modules::claude::sandbox::runner(...)`
  - Args:
    - ...
- `p6df::modules::claude::sandbox::select(sandbox_name)`
  - Args:
    - sandbox_name
- `path dir = p6df::modules::claude::sandbox::config_dir([sandbox_name=$P6_DFZ_CLAUDE_SANDBOX_NAME])`
  - Args:
    - OPTIONAL sandbox_name - [$P6_DFZ_CLAUDE_SANDBOX_NAME]
- `path dir = p6df::modules::claude::sandbox::dir([sandbox_name=$P6_DFZ_CLAUDE_SANDBOX_NAME])`
  - Args:
    - OPTIONAL sandbox_name - [$P6_DFZ_CLAUDE_SANDBOX_NAME]
- `path settings_file = p6df::modules::claude::sandbox::settings_file([sandbox_name=$P6_DFZ_CLAUDE_SANDBOX_NAME])`
  - Args:
    - OPTIONAL sandbox_name - [$P6_DFZ_CLAUDE_SANDBOX_NAME]
- `str dir = p6df::modules::claude::sandbox::create(sandbox_name, ...)`
  - Args:
    - sandbox_name
    - ...

##### p6df-claude/lib/sandboxes.sh

- `p6df::modules::claude::sandboxes::init()`

## Hierarchy

```text
.
├── init.zsh
├── lib
│   ├── sandbox.sh
│   └── sandboxes.sh
├── README.md
└── share

3 directories, 4 files
```

## Author

Philip M. Gollucci <pgollucci@p6m7g8.com>
