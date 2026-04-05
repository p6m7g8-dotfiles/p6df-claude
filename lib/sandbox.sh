# shellcheck shell=bash
######################################################################
#<
#
# Function: path dir = p6df::modules::claude::sandbox::dir([sandbox_name=$P6_DFZ_CLAUDE_SANDBOX_NAME])
#
#  Args:
#	OPTIONAL sandbox_name - [$P6_DFZ_CLAUDE_SANDBOX_NAME]
#
#  Returns:
#	path - dir
#
#  Environment:	 P6_DFZ_CLAUDE_SANDBOX_DIR P6_DFZ_CLAUDE_SANDBOX_NAME
#>
######################################################################
p6df::modules::claude::sandbox::dir() {
  local sandbox_name="${1:-$P6_DFZ_CLAUDE_SANDBOX_NAME}"

  local dir="$P6_DFZ_CLAUDE_SANDBOX_DIR/$sandbox_name"

  p6_return_path "$dir"
}

######################################################################
#<
#
# Function: path dir = p6df::modules::claude::sandbox::config_dir([sandbox_name=$P6_DFZ_CLAUDE_SANDBOX_NAME])
#
#  Args:
#	OPTIONAL sandbox_name - [$P6_DFZ_CLAUDE_SANDBOX_NAME]
#
#  Returns:
#	path - dir
#
#  Environment:	 P6_DFZ_CLAUDE_SANDBOX_NAME
#>
######################################################################
p6df::modules::claude::sandbox::config_dir() {
  local sandbox_name="${1:-$P6_DFZ_CLAUDE_SANDBOX_NAME}"

  local dir=$(p6df::modules::claude::sandbox::dir "$sandbox_name")

  p6_return_path "$dir"
}

######################################################################
#<
#
# Function: path settings_file = p6df::modules::claude::sandbox::settings_file([sandbox_name=$P6_DFZ_CLAUDE_SANDBOX_NAME])
#
#  Args:
#	OPTIONAL sandbox_name - [$P6_DFZ_CLAUDE_SANDBOX_NAME]
#
#  Returns:
#	path - settings_file
#
#  Environment:	 P6_DFZ_CLAUDE_SANDBOX_NAME
#>
######################################################################
p6df::modules::claude::sandbox::settings_file() {
  local sandbox_name="${1:-$P6_DFZ_CLAUDE_SANDBOX_NAME}"

  local config_dir=$(p6df::modules::claude::sandbox::config_dir "$sandbox_name")
  local settings_file="$config_dir/settings.json"

  p6_return_path "$settings_file"
}

######################################################################
#<
#
# Function: str dir = p6df::modules::claude::sandbox::create(sandbox_name, ...)
#
#  Args:
#	sandbox_name -
#	... - 
#
#  Returns:
#	str - dir
#
#  Environment:	 P6_DFZ_SRC_P6M7G8_DOTFILES_DIR
#>
######################################################################
p6df::modules::claude::sandbox::create() {
  local sandbox_name="$1"
  shift 1

  p6df::modules::claude::sandbox::select "$sandbox_name"

  local dir="$(p6df::modules::claude::sandbox::dir "$sandbox_name")"
  p6_dir_mk "$dir"

  local src="$P6_DFZ_SRC_P6M7G8_DOTFILES_DIR/p6df-claude/share/.claude"
  p6_file_symlink "$src/CLAUDE.md"   "$dir/CLAUDE.md"
  p6_file_symlink "$src/hooks"       "$dir/hooks"
  p6_file_symlink "$src/rules"       "$dir/rules"
  p6_file_symlink "$src/agents"      "$dir/agents"
  p6_file_symlink "$src/supervisor"  "$dir/supervisor"

  p6_return_str "$dir"
}

######################################################################
#<
#
# Function: p6df::modules::claude::sandbox::runner(...)
#
#  Args:
#	... - 
#
#  Environment:	 P6_DFZ_PROMPT_IN_CLAUDE
#>
######################################################################
p6df::modules::claude::sandbox::runner() {
  shift 0

  local config_dir=$(p6df::modules::claude::sandbox::config_dir)

  p6_env_export P6_DFZ_PROMPT_IN_CLAUDE 1
  CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD="$config_dir" claude "$@"
  p6_env_export_un P6_DFZ_PROMPT_IN_CLAUDE

  p6_return_void
}

######################################################################
#<
#
# Function: p6df::modules::claude::sandbox::select(sandbox_name)
#
#  Args:
#	sandbox_name -
#
#  Environment:	 P6_DFZ_CLAUDE_SANDBOX_NAME
#>
######################################################################
p6df::modules::claude::sandbox::select() {
  local sandbox_name="$1"

  p6_env_export "P6_DFZ_CLAUDE_SANDBOX_NAME" "$sandbox_name"

  p6_return_void
}
