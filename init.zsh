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
# Function: p6df::modules::claude::env::init()
#
#  Environment:	 DISABLE_ERROR_REPORTING DISABLE_TELEMETRY
#>
######################################################################
p6df::modules::claude::env::init() {
  local _module="$1"
  local _dir="$2"

  p6df::modules::claude::sandboxes::init

  # Recommended (changed)
  p6_env_export "DISABLE_TELEMETRY"      "${DISABLE_TELEMETRY:-1}"      # Opt out of Statsig telemetry.
  p6_env_export "DISABLE_ERROR_REPORTING" "${DISABLE_ERROR_REPORTING:-1}" # Opt out of Sentry error reporting.

  # Optional (not changed)
  # p6_env_export "CLAUDE_CODE_MAX_OUTPUT_TOKENS"          "${CLAUDE_CODE_MAX_OUTPUT_TOKENS:-}"				 # Max output tokens for most requests.
  # p6_env_export "MAX_THINKING_TOKENS"                    "${MAX_THINKING_TOKENS:-}"					 # Force a specific thinking budget (0 to disable).
  # p6_env_export "MAX_MCP_OUTPUT_TOKENS"                  "${MAX_MCP_OUTPUT_TOKENS:-25000}"				 # Max tokens in MCP tool responses (default: 25000).
  # p6_env_export "CLAUDE_CODE_AUTO_COMPACT_WINDOW"        "${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}"			 # Override auto-compaction context window size.
  # p6_env_export "CLAUDE_CODE_DISABLE_1M_CONTEXT"         "${CLAUDE_CODE_DISABLE_1M_CONTEXT:-}"			 # Disable 1M context window support (1).
  # p6_env_export "CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING"  "${CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING:-}"			 # Revert to fixed thinking budget (1).
  # p6_env_export "CLAUDE_CODE_EFFORT_LEVEL"               "${CLAUDE_CODE_EFFORT_LEVEL:-}"				 # Effort level: low, medium, high, max.
  # p6_env_export "CLAUDE_CODE_SHELL"                      "${CLAUDE_CODE_SHELL:-}"					 # Shell binary for Bash tool execution.
  # p6_env_export "CLAUDE_ENV_FILE"                        "${CLAUDE_ENV_FILE:-}"					 # Path to script sourced before each Bash command.
  # p6_env_export "CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR" "${CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR:-}"		 # Reset cwd to project dir after each Bash command (1).
  # p6_env_export "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC" "${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-}"		 # Disable all non-essential outbound traffic (bundles four below).
  # p6_env_export "DISABLE_AUTOUPDATER"                    "${DISABLE_AUTOUPDATER:-}"					 # Disable auto-updates (1).
  # p6_env_export "DISABLE_BUG_COMMAND"                    "${DISABLE_BUG_COMMAND:-}"					 # Disable /bug command (1).
  # p6_env_export "DISABLE_COST_WARNINGS"                  "${DISABLE_COST_WARNINGS:-}"					 # Disable cost warning messages (1).
  # p6_env_export "DISABLE_NON_ESSENTIAL_MODEL_CALLS"      "${DISABLE_NON_ESSENTIAL_MODEL_CALLS:-}"			 # Disable model calls for non-critical paths (1).
  # p6_env_export "CLAUDE_CODE_DISABLE_CRON"               "${CLAUDE_CODE_DISABLE_CRON:-}"				 # Disable background cron jobs.
  # p6_env_export "CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS" "${CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS:-}"		 # SessionEnd hook timeout in milliseconds.
  # p6_env_export "MCP_TIMEOUT"                            "${MCP_TIMEOUT:-}"						 # MCP server startup timeout in milliseconds.
  # p6_env_export "MCP_TOOL_TIMEOUT"                       "${MCP_TOOL_TIMEOUT:-}"					 # MCP tool execution timeout in milliseconds.
  # p6_env_export "ENABLE_CLAUDEAI_MCP_SERVERS"            "${ENABLE_CLAUDEAI_MCP_SERVERS:-}"				 # Enable claude.ai MCP servers (false to disable).
  # p6_env_export "CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD" "${CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD:-}"     # Load CLAUDE.md from --add-dir dirs (1).
  # p6_env_export "CLAUDE_CODE_USE_POWERSHELL_TOOL"        "${CLAUDE_CODE_USE_POWERSHELL_TOOL:-}"			 # Enable PowerShell tool on Windows (1).

  p6_return_void
}

######################################################################
#<
#
# Function: p6df::modules::claude::path::init()
#
#  Environment:	 HOME
#>
######################################################################
p6df::modules::claude::path::init() {
  local _module="$1"
  local _dir="$2"

  p6df::core::path::if "$HOME/.claude/bin"

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
  local _module="$1"
  local _dir="$2"

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

  # sandboxes
  p6_alias "p6_claude" "p6df::modules::claude::sandbox::runner"
  p6_alias "clss"  "p6df::modules::claude::sandbox::select"

  p6_alias "clacl" "p6df::modules::claude::sandbox::select arkestro; p6df::modules::claude::sandbox::runner"
  p6_alias "clp6cl" "p6df::modules::claude::sandbox::select p6;      p6df::modules::claude::sandbox::runner"

  p6_return_void
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
# Function: p6df::modules::claude::langs()
#
#  Environment:	 P6_DFZ_CLAUDE_SANDBOX_NAME
#>
######################################################################
p6df::modules::claude::langs() {

  p6df::modules::claude::sandbox::create arkestro
  p6df::modules::claude::sandbox::create p6

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
# Function: words claude = p6df::modules::claude::profile::mod()
#
#  Returns:
#	words - claude
#
#>
######################################################################
p6df::modules::claude::profile::mod() {

  p6_return_words 'claude' '$ANTHROPIC_API_KEY' '$ANTHROPIC_AUTH_TOKEN' '$ANTHROPIC_MODEL' '$ANTHROPIC_BASE_URL'
}

