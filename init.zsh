# shellcheck shell=bash
######################################################################
#<
#
# Function: p6df::modules::claude::deps()
#
#>
######################################################################
p6df::modules::claude::deps() {
  ModuleDeps=(
    p6m7g8-dotfiles/p6df-anthropic
  )
}

######################################################################
#<
#
# Function: p6df::modules::claude::external::brews()
#
#>
######################################################################
p6df::modules::claude::external::brews() {

  p6df::core::homebrew::cli::brew::install --cask claude-code
  p6df::core::homebrew::cli::brew::install --cask claude
  p6df::core::homebrew::cli::brew::install claude-cmd
  p6df::core::homebrew::cli::brew::install claude-code-templates
  p6df::core::homebrew::cli::brew::install claude-hooks

  p6_return_void
}

######################################################################
#<
#
# Function: p6df::modules::claude::home::symlinks()
#
#  Environment:	 HOME P6_DFZ_SRC_P6M7G8_DOTFILES_DIR
#>
######################################################################
p6df::modules::claude::home::symlinks() {
  local src="$P6_DFZ_SRC_P6M7G8_DOTFILES_DIR/p6df-claude/share/.claude"

  # Core config
  p6_file_symlink "$src/CLAUDE.md"       "$HOME/.claude/CLAUDE.md"
  p6_file_symlink "$src/settings.json"   "$HOME/.claude/settings.json"

  # Hooks directory
  p6_file_symlink "$src/hooks"           "$HOME/.claude/hooks"

  # Rules and agents
  p6_file_symlink "$src/rules"           "$HOME/.claude/rules"
  p6_file_symlink "$src/agents"          "$HOME/.claude/agents"

  # Supervisor
  p6_file_symlink "$src/supervisor"      "$HOME/.claude/supervisor"

  p6_return_void
}

######################################################################
#<
#
# Function: str str = p6df::modules::claude::prompt::mod()
#
#  Returns:
#	str - str
#
#  Environment:	 CLAUDE_CODE_OAUTH_TOKEN CLAUDE_CONFIG_DIR P6_DFZ_PROFILE_CLAUDE
#>
######################################################################
p6df::modules::claude::prompt::mod() {
  local str=""

  if p6_string_blank_NOT "$P6_DFZ_PROFILE_CLAUDE"; then
    str="claude:\t\t  $P6_DFZ_PROFILE_CLAUDE:"
    if p6_string_blank_NOT "$CLAUDE_CODE_OAUTH_TOKEN"; then
      str=$(p6_string_append "$str" "oauth" " ")
    fi
    if p6_string_blank_NOT "$CLAUDE_CONFIG_DIR"; then
      str=$(p6_string_append "$str" "[$CLAUDE_CONFIG_DIR]" " ")
    fi
  fi

  p6_return_str "$str"
}

######################################################################
#<
#
# Function: p6df::modules::claude::profile::on(profile, code)
#
#  Args:
#	profile -
#	code - shell code block (export CLAUDE_CODE_OAUTH_TOKEN=...)
#
#  Environment:	 CLAUDE_CODE_OAUTH_TOKEN P6_DFZ_PROFILE_CLAUDE
#>
######################################################################
p6df::modules::claude::profile::on() {
  local profile="$1"
  local code="$2"

  p6_run_code "$code"

  p6_env_export "P6_DFZ_PROFILE_CLAUDE" "$profile"

  p6_return_void
}

######################################################################
#<
#
# Function: p6df::modules::claude::profile::off(code)
#
#  Args:
#	code - shell code block previously passed to profile::on
#
#  Environment:	 CLAUDE_CODE_OAUTH_TOKEN P6_DFZ_PROFILE_CLAUDE
#>
######################################################################
p6df::modules::claude::profile::off() {
  local code="$1"

  p6_env_unset_from_code "$code"
  p6_env_export_un P6_DFZ_PROFILE_CLAUDE

  p6_return_void
}

######################################################################
#<
#
# Function: p6df::modules::claude::init(_module, dir)
#
#  Args:
#	_module -
#	dir -
#
#  Environment:	 HOME
#>
######################################################################
p6df::modules::claude::init() {
  local _module="$1"
  local dir="$2"

  p6df::modules::claude::env::init

  p6df::core::path::if "$HOME/.claude/bin"

  p6_return_void
}

######################################################################
#<
#
# Function: p6df::modules::claude::vscodes::config()
#
#>
######################################################################
p6df::modules::claude::vscodes::config() {

  cat <<'EOF'
  "claudeCode.preferredLocation": "sidebar"
EOF

  p6_return_void
}

######################################################################
#<
#
# Function: p6df::modules::claude::env::init()
#
#  Environment:	 CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR CLAUDE_CODE_AUTO_COMPACT_WINDOW CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD CLAUDE_CODE_DISABLE_1M_CONTEXT CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING CLAUDE_CODE_DISABLE_CRON CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC CLAUDE_CODE_EFFORT_LEVEL CLAUDE_CODE_MAX_OUTPUT_TOKENS CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS CLAUDE_CODE_SHELL CLAUDE_CODE_USE_POWERSHELL_TOOL CLAUDE_ENV_FILE DISABLE_AUTOUPDATER DISABLE_BUG_COMMAND DISABLE_COST_WARNINGS DISABLE_ERROR_REPORTING DISABLE_NON_ESSENTIAL_MODEL_CALLS DISABLE_TELEMETRY ENABLE_CLAUDEAI_MCP_SERVERS MAX_MCP_OUTPUT_TOKENS MAX_THINKING_TOKENS MCP_TIMEOUT MCP_TOOL_TIMEOUT
#>
######################################################################
p6df::modules::claude::env::init() {

  # Recommended (changed)
  p6_env_export "DISABLE_TELEMETRY"      "${DISABLE_TELEMETRY:-1}"      # Opt out of Statsig telemetry.
  p6_env_export "DISABLE_ERROR_REPORTING" "${DISABLE_ERROR_REPORTING:-1}" # Opt out of Sentry error reporting.

  # Optional (not changed)
  # p6_env_export "CLAUDE_CODE_MAX_OUTPUT_TOKENS"          "${CLAUDE_CODE_MAX_OUTPUT_TOKENS:-}"          # Max output tokens for most requests.
  # p6_env_export "MAX_THINKING_TOKENS"                    "${MAX_THINKING_TOKENS:-}"                    # Force a specific thinking budget (0 to disable).
  # p6_env_export "MAX_MCP_OUTPUT_TOKENS"                  "${MAX_MCP_OUTPUT_TOKENS:-25000}"             # Max tokens in MCP tool responses (default: 25000).
  # p6_env_export "CLAUDE_CODE_AUTO_COMPACT_WINDOW"        "${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}"        # Override auto-compaction context window size.
  # p6_env_export "CLAUDE_CODE_DISABLE_1M_CONTEXT"         "${CLAUDE_CODE_DISABLE_1M_CONTEXT:-}"         # Disable 1M context window support (1).
  # p6_env_export "CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING"  "${CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING:-}"  # Revert to fixed thinking budget (1).
  # p6_env_export "CLAUDE_CODE_EFFORT_LEVEL"               "${CLAUDE_CODE_EFFORT_LEVEL:-}"               # Effort level: low, medium, high, max.
  # p6_env_export "CLAUDE_CODE_SHELL"                      "${CLAUDE_CODE_SHELL:-}"                      # Shell binary for Bash tool execution.
  # p6_env_export "CLAUDE_ENV_FILE"                        "${CLAUDE_ENV_FILE:-}"                        # Path to script sourced before each Bash command.
  # p6_env_export "CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR" "${CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR:-}" # Reset cwd to project dir after each Bash command (1).
  # p6_env_export "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-}" # Disable all non-essential outbound traffic (bundles four below).
  # p6_env_export "DISABLE_AUTOUPDATER"                    "${DISABLE_AUTOUPDATER:-}"                    # Disable auto-updates (1).
  # p6_env_export "DISABLE_BUG_COMMAND"                    "${DISABLE_BUG_COMMAND:-}"                    # Disable /bug command (1).
  # p6_env_export "DISABLE_COST_WARNINGS"                  "${DISABLE_COST_WARNINGS:-}"                  # Disable cost warning messages (1).
  # p6_env_export "DISABLE_NON_ESSENTIAL_MODEL_CALLS"      "${DISABLE_NON_ESSENTIAL_MODEL_CALLS:-}"      # Disable model calls for non-critical paths (1).
  # p6_env_export "CLAUDE_CODE_DISABLE_CRON"               "${CLAUDE_CODE_DISABLE_CRON:-}"               # Disable background cron jobs.
  # p6_env_export "CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS" "${CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS:-}" # SessionEnd hook timeout in milliseconds.
  # p6_env_export "MCP_TIMEOUT"                            "${MCP_TIMEOUT:-}"                            # MCP server startup timeout in milliseconds.
  # p6_env_export "MCP_TOOL_TIMEOUT"                       "${MCP_TOOL_TIMEOUT:-}"                       # MCP tool execution timeout in milliseconds.
  # p6_env_export "ENABLE_CLAUDEAI_MCP_SERVERS"            "${ENABLE_CLAUDEAI_MCP_SERVERS:-}"            # Enable claude.ai MCP servers (false to disable).
  # p6_env_export "CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD" "${CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD:-}" # Load CLAUDE.md from --add-dir dirs (1).
  # p6_env_export "CLAUDE_CODE_USE_POWERSHELL_TOOL"        "${CLAUDE_CODE_USE_POWERSHELL_TOOL:-}"        # Enable PowerShell tool on Windows (1).

  p6_return_void
}

######################################################################
#<
#
# Function: p6df::modules::claude::aliases::init()
#
#>
######################################################################
p6df::modules::claude::aliases::init() {

  # core
  p6_alias "cl" "claude"
  p6_alias "clh" "claude --help"
  p6_alias "clv" "claude --version"

  # sessions
  p6_alias "clsf" "claude --resume --fork-session"
  p6_alias "clsn" "claude --no-session-persistence"

  # common workflows
  p6_alias "clp"  "claude --print"
  p6_alias "clii" "claude --interactive"
  p6_alias "clc"  "claude --continue"
  p6_alias "clr"  "claude --resume"

  # debugging / verbosity
  p6_alias "cld" "CLAUDE_DEBUG=1 claude"
  p6_alias "clvv" "CLAUDE_DEBUG=1 CLAUDE_VERBOSE=1 claude"

  # piping / unix-style usage
  p6_alias "clx" 'xargs -I{} claude --print <<< "{}"'
  p6_alias "clcat" "claude --print"

  # config / env inspection
  p6_alias "clenv" 'env | p6_filter_row_select_icase "claude"'

  p6_return_void
}
