# shellcheck shell=bash

######################################################################
#<
#
# Function: p6df::modules::claude::sandboxes::init()
#
#  Environment:	 P6_DFZ_CLAUDE_SANDBOX_DIR
#>
######################################################################
p6df::modules::claude::sandboxes::init() {

  if p6_string_blank_NOT "$P6_DFZ_CLAUDE_SANDBOX_DIR"; then
    p6_dir_mk "$P6_DFZ_CLAUDE_SANDBOX_DIR"
  fi

  p6_return_void
}
