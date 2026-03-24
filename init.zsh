# shellcheck shell=bash
######################################################################
#<
#
# Function: p6df::modules::claudecode::deps()
#
#>
######################################################################
p6df::modules::claudecode::deps() {
  ModuleDeps=(
    p6m7g8-dotfiles/p6common
  )
}

######################################################################
#<
#
# Function: p6df::modules::claudecode::vscodes::config()
#
#>
######################################################################
p6df::modules::claudecode::vscodes::config() {

  cat <<'EOF'
  "claudeCode.preferredLocation": "sidebar"
EOF

  p6_return_void
}

######################################################################
#<
#
# Function: p6df::modules::claudecode::init(_module, dir)
#
#  Args:
#	_module -
#	dir -
#
#  Environment:	 HOME
#>
######################################################################
p6df::modules::claudecode::init() {
  local _module="$1"
  local dir="$2"

  p6df::core::path::if "$HOME/.claude/bin"

  p6_return_void
}

######################################################################
#<
#
# Function: p6df::modules::claudecode::external::brew()
#
#>
######################################################################
p6df::modules::claudecode::external::brew() {

  p6df::core::homebrew::cli::brew::install install claude-cmd
  p6df::core::homebrew::cli::brew::install install claude-code-templates
  p6df::core::homebrew::cli::brew::install install claude-hooks

  p6df::core::homebrew::cli::brew::install install --cask claude
  p6df::core::homebrew::cli::brew::install install --cask claude-code

  p6_return_void
}

######################################################################
#<
#
# Function: p6df::modules::claudecode::aliases::init()
#
#>
######################################################################
p6df::modules::claudecode::aliases::init() {

  # core
  p6_alias "cl" "claude"
  p6_alias "clh" "claude --help"
  p6_alias "clv" "claude --version"

  # sessions
  p6_alias "clsf" "claude --resume --fork-session"
  p6_alias "clsn" "claude --no-session-persistence"

  # common workflows
  p6_alias "clp" "claude --print"
  p6_alias "cli" "claude --interactive"
  p6_alias "clc" "claude --continue"
  p6_alias "clr" "claude --resume"

  # debugging / verbosity
  p6_alias "cld" "CLAUDE_DEBUG=1 claude"
  p6_alias "clvv" "CLAUDE_DEBUG=1 CLAUDE_VERBOSE=1 claude"

  # piping / unix-style usage
  p6_alias "clx" 'xargs -I{} claude --print <<< "{}"'
  p6_alias "clcat" "claude --print <"

  # config / env inspection
  p6_alias "clenv" 'env | p6_filter_row_select_icase "claude"'

  p6_return_void
}

######################################################################
#<
#
# Function: str str = p6df::modules::claudecode::prompt::mod()
#
#  Returns:
#	str - str
#
#  Environment:	 CLAUDE_CODE_OAUTH_TOKEN P6_DFZ_PROFILE_CLAUDE
#>
######################################################################
p6df::modules::claudecode::prompt::mod() {

  local str
  if p6_string_blank_NOT "$P6_DFZ_PROFILE_CLAUDE"; then
    if p6_string_blank_NOT "$CLAUDE_CODE_OAUTH_TOKEN"; then
      str="claudecode:\t  $P6_DFZ_PROFILE_CLAUDE: oauth"
    fi
  fi

  p6_return_str "$str"
}

######################################################################
#<
#
# Function: p6df::modules::claudecode::profile::on(profile, [token=])
#
#  Args:
#	profile -
#	OPTIONAL token - []
#
#  Environment:	 ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN P6_DFZ_PROFILE_CLAUDE
#>
######################################################################
p6df::modules::claudecode::profile::on() {
  local profile="$1"
  local token="${2:-}"

  p6_env_export "P6_DFZ_PROFILE_CLAUDE" "$profile"

  if p6_string_blank_NOT "$token"; then
    p6_env_export "CLAUDE_CODE_OAUTH_TOKEN" "$token"
    p6_env_export "ANTHROPIC_API_KEY" "$token"
  elif p6_string_blank_NOT "$CLAUDE_CODE_OAUTH_TOKEN"; then
    p6_env_export "ANTHROPIC_API_KEY" "$CLAUDE_CODE_OAUTH_TOKEN"
  else
    p6_env_export_un ANTHROPIC_API_KEY
  fi

  p6_return_void
}

######################################################################
#<
#
# Function: p6df::modules::claudecode::profile::off()
#
#  Environment:	 ANTHROPIC_API_KEY CLAUDE_CODE_OAUTH_TOKEN P6_DFZ_PROFILE_CLAUDE
#>
######################################################################
p6df::modules::claudecode::profile::off() {

  p6_env_export_un P6_DFZ_PROFILE_CLAUDE
  p6_env_export_un CLAUDE_CODE_OAUTH_TOKEN
  p6_env_export_un ANTHROPIC_API_KEY

  p6_return_void
}
