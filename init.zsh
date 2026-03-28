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

  p6df::modules::homebrew::cli::brew::install --cask claude-code
  p6df::modules::homebrew::cli::brew::install --cask claude
  p6df::modules::homebrew::cli::brew::install claude-cmd
  p6df::modules::homebrew::cli::brew::install claude-code-templates
  p6df::modules::homebrew::cli::brew::install claude-hooks

  p6_return_void
}

######################################################################
#<
#
# Function: p6df::modules::claude::home::symlink()
#
#  Environment:	 HOME P6_DFZ_SRC_P6M7G8_DOTFILES_DIR
#>
######################################################################
p6df::modules::claude::home::symlink() {

  p6_file_symlink "$P6_DFZ_SRC_P6M7G8_DOTFILES_DIR/p6df-claude/share/.claude/CLAUDE.md" "$HOME/.claude/CLAUDE.md"

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
#  Environment:	 CLAUDE_CODE_OAUTH_TOKEN P6_DFZ_PROFILE_CLAUDE
#>
######################################################################
p6df::modules::claude::prompt::mod() {
  local str=""

  if p6_string_blank_NOT "$P6_DFZ_PROFILE_CLAUDE"; then
    str="claude:\t\t  $P6_DFZ_PROFILE_CLAUDE:"
    if p6_string_blank_NOT "$CLAUDE_CODE_OAUTH_TOKEN"; then
      str=$(p6_string_append "$str" "oauth" " ")
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
# Function: p6df::modules::claude::code::init(_module, dir)
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

  p6df::core::path::if "$HOME/.claude/bin"

  p6_return_void
}

######################################################################
#<
#
# Function: p6df::modules::claude::code::vscodes::config()
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
# Function: p6df::modules::claude::code::aliases::init()
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
