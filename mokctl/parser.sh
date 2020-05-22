# PA - PArser

# GLOBALS
# Don't change any globals

# Constants
readonly LABELKEY="MokCluster"
readonly BASEIMAGENAME="mok-centos-7"
readonly OK=0
readonly ERROR=1
readonly FALSE=0
readonly TRUE=1
readonly STOP=2
readonly SPINNER=('◐' '◓' '◑' '◒')

colyellow=$(tput setaf 3)
colgreen=$(tput setaf 2)
colred=$(tput setaf 1)
colreset=$(tput sgr0)
probablysuccess="$colyellow✓$colreset"
success="$colgreen✓$colreset"
failure="$colred✕$colreset"

# The initial state of the parser
STATE="COMMAND"

# Parser sets these:
COMMAND=
SUBCOMMAND=
CREATE_CLUSTER_NAME=
BUILD_IMAGE_K8SVER=
CREATE_CLUSTER_K8SVER=
CREATE_CLUSTER_WITH_LB=
CREATE_CLUSTER_SKIPLBSETUP=
CREATE_CLUSTER_NUM_MASTERS=
CREATE_CLUSTER_NUM_WORKERS=
CREATE_CLUSTER_SKIPMASTERSETUP=
CREATE_CLUSTER_SKIPWORKERSETUP=
DELETE_CLUSTER_NAME=
GET_CLUSTER_NAME=
GET_CLUSTER_SHOW_HEADER=
EXEC_CONTAINER_NAME=

# For outputting errors
E="/dev/stderr"
ERR_CALLED=

PODMANIMGPREFIX=
BUILD_GET_PREBUILT=
CONTAINERRT=

# Directory to unpack the build files
DOCKERBUILDTMPDIR=

# For the spinning progress animation
RUNWITHPROGRESS_OUTPUT=

# END GLOBALS

# ===========================================================================
#                   FUNCTIONS FOR PARSING THE COMMAND LINE
# ===========================================================================

# ---------------------------------------------------------------------------
usage() {

  # Every tool, no matter how small, should have help text!

  case $COMMAND in
  create)
    create_usage
    return $OK
    ;;
  delete)
    delete_usage
    return $OK
    ;;
  build)
    build_usage
    return $OK
    ;;
  get)
    get_usage
    return $OK
    ;;
  exec)
    exec_usage
    return $OK
    ;;
  esac

  cat <<'EnD'

Usage: mokctl [-h] <command> [subcommand] [OPTIONS...]
 
Global options:
 
  --help
  -h     - This help text
 
Where command can be one of:
 
  create - Add item(s) to the system.
  delete - Delete item(s) from the system.
  build  - Build item(s) used by the system.
  get    - Get details about items in the system.
  exec   - 'Log in' to the container.

EnD

  # Output individual help pages
  create_usage
  delete_usage
  build_usage
  get_usage
  exec_usage

  cat <<'EnD'
EXAMPLES
 
Get a list of mok clusters
 
  mokctl get clusters
 
Build the image used for masters and workers:
 
  mokctl build image
 
Create a single node cluster:
Note that the master node will be made schedulable for pods.
 
  mokctl create cluster mycluster 1 0
 
Create a single master and single node cluster:
Note that the master node will NOT be schedulable for pods.
 
  mokctl create cluster mycluster 1 1
 
Delete a cluster:
 
  mokctl delete cluster mycluster

EnD
}

# ---------------------------------------------------------------------------
parse_options() {

  # Uses a state machine to check all command line arguments
  # Args:
  #   arg1 - The arguments given to mokctl by the user on the command line

  set -- "$@"
  local ARGN=$#
  while [ "$ARGN" -ne 0 ]; do
    case $1 in
    --skipmastersetup)
      verify_option '--skipmastersetup' || return $ERROR
      CREATE_CLUSTER_SKIPMASTERSETUP=$TRUE
      ;;
    --skipworkersetup)
      verify_option '--skipworkersetup' || return $ERROR
      CREATE_CLUSTER_SKIPWORKERSETUP=$TRUE
      ;;
    --skiplbsetup)
      verify_option '--skiplbsetup' || return $ERROR
      CREATE_CLUSTER_SKIPLBSETUP="$TRUE"
      ;;
    --with-lb)
      verify_option '--with-lb' || return $ERROR
      CREATE_CLUSTER_WITH_LB="$TRUE"
      ;;
    --k8sver)
      verify_option '--k8sver' || return $ERROR
      # enable later -> BUILD_IMAGE_K8SVER="$1"
      shift
      ;;
    --get-prebuilt-image)
      verify_option '--get-prebuilt-image' || return $ERROR
      BI_set_useprebuiltimage "$TRUE"
      ;;
    --help) ;&
    -h)
      usage
      return $STOP
      ;;
    --?*)
      usage
      printf 'Invalid option: "%s"\n' "$1" >"$E"
      return $ERROR
      ;;
    ?*)
      case "$STATE" in
      COMMAND)
        check_command_token "$1"
        [[ $? -eq $ERROR ]] && {
          usage
          printf 'Invalid COMMAND, "%s".\n\n' "$1" >"$E"
          return $ERROR
        }
        ;;
      SUBCOMMAND)
        check_subcommand_token "$1"
        [[ $? -eq $ERROR ]] && {
          usage
          printf 'Invalid SUBCOMMAND for %s, "%s".\n\n' "$COMMAND" "$1" >"$E"
          return $ERROR
        }
        ;;
      OPTION)
        check_option_token "$1"
        [[ $? -eq $ERROR ]] && {
          usage
          printf 'Invalid OPTION for %s %s, "%s".\n\n' "$COMMAND" "$SUBCOMMAND" "$1" >"$E"
          return $ERROR
        }
        ;;
      OPTION2)
        check_option2_token "$1"
        [[ $? -eq $ERROR ]] && {
          usage
          printf 'Invalid OPTION for %s %s, "%s".\n\n' "$COMMAND" "$SUBCOMMAND" "$1" >"$E"
          return $ERROR
        }
        ;;
      OPTION3)
        check_option3_token "$1"
        [[ $? -eq $ERROR ]] && {
          usage
          printf 'Invalid OPTION for %s %s, "%s".\n\n' "$COMMAND" "$SUBCOMMAND" "$1" >"$E"
          return $ERROR
        }
        ;;
      END)
        usage
        printf 'ERROR No more options expected, "%s" is unexpected for "%s %s"\n' \
          "$1" "$COMMAND" "$SUBCOMMAND" >"$E"
        return $ERROR
        ;;
      ?*)
        printf 'Internal ERROR. Invalid state "%s"\n' "$STATE" >"$E"
        return $ERROR
        ;;
      esac
      ;;
    esac
    shift 1
    ARGN=$((ARGN - 1))
  done

  [[ -z $COMMAND ]] && {
    usage
    printf 'No COMMAND supplied\n' >"$E"
    return $ERROR
  }
  [[ -z $SUBCOMMAND ]] && {
    usage
    printf 'No SUBCOMMAND supplied\n' >"$E"
    return $ERROR
  }

  return $OK
}

# ===========================================================================
#                    COMMAND, SUBCOMMAND, OPTION PROCESSING
# ===========================================================================

# ---------------------------------------------------------------------------
check_command_token() {

  # Check for a valid token in command state
  # Args:
  #   arg1 - token

  case $1 in
  create)
    COMMAND="create"
    STATE="SUBCOMMAND"
    ;;
  delete)
    COMMAND="delete"
    STATE="SUBCOMMAND"
    ;;
  build)
    COMMAND="build"
    STATE="SUBCOMMAND"
    ;;
  get)
    COMMAND="get"
    STATE="SUBCOMMAND"
    ;;
  exec)
    COMMAND="exec"
    SUBCOMMAND="unused"
    STATE="OPTION"
    ;;
  ?*) return $ERROR ;;
  esac
}

# ---------------------------------------------------------------------------
check_subcommand_token() {

  # Check for a valid token in subcommand state
  # Args:
  #   arg1 - token

  case $COMMAND in
  create) check_create_subcommand_token "$1" ;;
  delete) check_delete_subcommand_token "$1" ;;
  build) check_build_subcommand_token "$1" ;;
  get) check_get_subcommand_token "$1" ;;
  esac
}

# ---------------------------------------------------------------------------
check_create_subcommand_token() {

  # Check for a valid token in subcommand state
  # Args:
  #   arg1 - token

  case $1 in
  cluster) SUBCOMMAND="cluster" ;;
  ?*) return $ERROR ;;
  esac

  STATE="OPTION"

  return $OK
}

# ---------------------------------------------------------------------------
check_delete_subcommand_token() {

  # Check for a valid token in subcommand state
  # Args:
  #   arg1 - token

  case $1 in
  cluster) SUBCOMMAND="cluster" ;;
  ?*) return $ERROR ;;
  esac

  STATE=OPTION
}

# ---------------------------------------------------------------------------
check_build_subcommand_token() {

  # Check for a valid token in subcommand state
  # Args:
  #   arg1 - token

  case $1 in
  image) SUBCOMMAND="image" ;;
  ?*) return $ERROR ;;
  esac

  STATE=END
}

# ---------------------------------------------------------------------------
check_get_subcommand_token() {

  # Check for a valid token in subcommand state
  # Args:
  #   arg1 - token

  case $1 in
  clusters) ;&
  cluster) SUBCOMMAND="cluster" ;;
  ?*) return $ERROR ;;
  esac

  STATE=OPTION
}

# ---------------------------------------------------------------------------
check_option_token() {

  # Check for a valid token in option state
  # Args:
  #   arg1 - token

  case $COMMAND in
  create)
    case $SUBCOMMAND in
    cluster)
      CREATE_CLUSTER_NAME="$1"
      STATE="OPTION2"
      ;;
    esac
    ;;
  delete)
    case $SUBCOMMAND in
    cluster)
      DELETE_CLUSTER_NAME="$1"
      STATE="END"
      ;;
    esac
    ;;
  get)
    case $SUBCOMMAND in
    cluster)
      GET_CLUSTER_NAME="$1"
      STATE="END"
      ;;
    esac
    ;;
  exec)
    EXEC_CONTAINER_NAME="$1"
    STATE="END"
    ;;
  esac
}

# ---------------------------------------------------------------------------
check_option2_token() {

  # Check for a valid token in option2 state
  # Args:
  #   arg1 - token

  case $COMMAND in
  create)
    case $SUBCOMMAND in
    cluster)
      CREATE_CLUSTER_NUM_MASTERS="$1"
      STATE="OPTION3"
      ;;
    esac
    ;;
  delete)
    case $SUBCOMMAND in
    cluster)
      return $ERROR
      ;;
    esac
    ;;
  esac
}

# ---------------------------------------------------------------------------
check_option3_token() {

  # Check for a valid token in option3 state
  # Args:
  #   arg1 - token

  case $COMMAND in
  create)
    case $SUBCOMMAND in
    cluster)
      CREATE_CLUSTER_NUM_WORKERS="$1"
      STATE="END"
      ;;
    esac
    ;;
  delete)
    case $SUBCOMMAND in
    cluster)
      return $ERROR
      ;;
    esac
    ;;
  esac
}

# ===========================================================================
#                              FLAG PROCESSING
# ===========================================================================

# ---------------------------------------------------------------------------
verify_option() {

  # Check that the sent option is valid for the command-subcommand or global
  # options.
  # Args:
  #   arg1 - The option to check.

  case "$COMMAND$SUBCOMMAND" in
  create) ;& # Treat flags located just before
  delete) ;& # or just after COMMAND
  build) ;&  # as global options.
  get) ;&
  '')
    check_valid_global_opts "$1"
    ;;
  createcluster)
    check_valid_create_cluster_opts "$1"
    ;;
  deletecluster)
    check_valid_delete_cluster_opts "$1"
    ;;
  buildimage)
    BI_check_valid_options "$1"
    ;;
  getcluster)
    check_valid_get_cluster_opts "$1"
    ;;
  esac && return $OK

  return $ERROR
}

# ---------------------------------------------------------------------------
check_valid_global_opts() {

  # Args:
  #   arg1 - The option to check.

  local int validopts=(
    "--help"
    "-h"
  )

  for int in "${validopts[@]}"; do
    [[ $1 == "$int" ]] && return $OK
  done

  usage
  printf 'ERROR: "%s" is not a valid global option.\n' "$1" >"$E"
  return $ERROR
}

# ---------------------------------------------------------------------------
check_valid_create_cluster_opts() {

  # Args:
  #   arg1 - The option to check.

  local opt validopts=(
    "--help"
    "-h"
    "--skipmastersetup"
    "--skipworkersetup"
    "--skiplbsetup"
    "--k8sver"
    "--with-lb"
  )

  for opt in "${validopts[@]}"; do
    [[ $1 == "$opt" ]] && return $OK
  done

  usage
  printf 'ERROR: "%s" is not a valid "create cluster" option.\n' "$1" >"$E"
  return $ERROR
}

# ---------------------------------------------------------------------------
check_valid_delete_cluster_opts() {

  # Args:
  #   arg1 - The option to check.

  local opt validopts=(
    "--help"
    "-h"
  )

  for opt in "${validopts[@]}"; do
    [[ $1 == "$opt" ]] && return $OK
  done

  usage
  printf 'ERROR: "%s" is not a valid "delete cluster" option.\n' "$1" >"$E"
  return $ERROR
}

# ---------------------------------------------------------------------------
check_valid_get_cluster_opts() {

  # Args:
  #   arg1 - The option to check.

  local opt validopts=(
    "--help"
    "-h"
  )

  for opt in "${validopts[@]}"; do
    [[ $1 == "$opt" ]] && return $OK
  done

  usage
  printf 'ERROR: "%s" is not a valid "get cluster" option.\n' "$1" >"$E"
  return $ERROR
}

# ---------------------------------------------------------------------------
check_valid_exec_cluster_opts() {

  # Args:
  #   arg1 - The option to check.

  local opt validopts=(
    "--help"
    "-h"
  )

  for opt in "${validopts[@]}"; do
    [[ $1 == "$opt" ]] && return $OK
  done

  usage
  printf 'ERROR: "%s" is not a valid "get cluster" option.\n' "$1" >"$E"
  return $ERROR
}

# vim:ft=sh:sw=2:et:ts=2: