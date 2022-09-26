set -e

_ARGV="$@"

source .env

IMAGE_NAME="$(basename $PWD)"
CONTAINER_PREFIX="$(basename $PWD)_${USER}"
REMOTE_PWD="$(echo $PWD | sed -e 's/^\/Users/\/home/')"
NETWORK_NAME="$(basename $PWD)_default"

red=$(tput setaf 1)
yellow=$(tput setaf 3)
green=$(tput setaf 2)
reset=$(tput sgr0)

error()       { echo -e "\033[0;31m$*\033[0m"; }
warning()     { echo -e "\033[1;33m$*\033[0m"; }
die()         { [[ ! -z $1 ]] && error "ERROR: $1"; return 1; }
timestamp()   { echo $(date +"%Y%m%d%H%M%S"); }
log()         { echo "[ $(date +"%Y-%m-%d %H:%M") ] $1" |tee -a $2; }
run()         { echo $*; $*; }
start_TIMER() { TIMER=$(date +%s); }
stop_TIMER()  { TIMER=$(($(date +%s) - $TIMER)); }

remote_exec() { ssh $REMOTE_HOST "cd $REMOTE_PWD; $*"; }

# running script on remote server with hostname $REMOTE_HOST
run_on_remote_host() {
  if [[ ! $(hostname) == $REMOTE_HOST ]]; then 
    echo "This script runs on $REMOTE_HOST"
    ssh -t $REMOTE_HOST "cd $REMOTE_PWD; $0 $_ARGV"
    return 1
  fi
}

_ask_SELECTION() {
  local accept_other=false
  local accept_multiple=false
  local use_string=false
  [[ $1 == "ACCEPT_OTHER"    ]] && accept_other=true    && shift
  [[ $1 == "ACCEPT_MULTIPLE" ]] && accept_multiple=true && shift
  [[ $1 == "USE_STRING"      ]] && use_string=true      && shift

  local glob=($*)   # support {,} globbing
  local selections=()

  local i=0
  for s in "${glob[@]}"; do
      if [[ $use_string == true || -e $s ]]; then
          echo "$i: $s"
          selections+=($s)
          ((i=i+1))
      fi
  done

  [[ $i == 0 ]] && echo "No selection found" && return 1

  local k
  local options="[0"
  [[ $i -gt 1 ]] && options+="-$(($i-1))]" || options+="]"
  [[ $accept_other    == true ]] && options+=", or enter other"
  [[ $accpet_multiple == true ]] && options+=", can select multiple"

  read -ep "select $options: " k

  if [[ "$k" =~ ^[0-9]+$ && "$k" -ge 0 && "$k" -lt $i ]]; then
      SELECTION="${selections[$k]}"
      echo "You selected: $SELECTION"
  elif [[ $accept_other == true ]]; then
      SELECTION="$k"
      echo "You entered: $SELECTION"
  elif [[ $accept_multiple == true ]]; then
      arr=()
      k=($k)
      for i in ${k[@]}; do arr+=("${selections[$i]}"); done
      SELECTION="${arr[*]}"
      echo "You selected: $SELECTION"
  else
      echo "Invalid selection" && return 1
  fi
  echo
}

#usage: ask_SELCTION "print" (ACCEPT_OTHER | ACCEPT_MULTIPLE | USE_STRING) $*/*_PATH -> save $SELECTION 

ask_SELECTION() {
  local k=$1 p=${PARAMS[$1]}
  shift
  if [[ -z "$p" ]]; then
      echo "select ${k}:"
      _ask_SELECTION $*
  else
      echo "${k} = $p"
      SELECTION="$p"
  fi
}

# functions that must be ran on remote host (linux or docker hoster)

#usage: create docker network

create_network() {
  local network=$1
  [[ -z $network ]] && network=$NETWORK_NAME
  if [[ -z $(docker network ls | grep $network) ]]; then
    docker network create $network > /dev/null 2>&1
  fi
}
remove_network() {
  local network=$1
  [[ -z $network ]] && network=$NETWORK_NAME
  if [[ $(docker network ls | grep $network) ]]; then
    docker network rm $network > /dev/null 2>&1
  fi
}

# usage: find_free_port "PORT_MIN,PORT_MAX"
find_free_port() {
  local port_range=($( echo $1 | tr "," "\n" ) )
  min_port_num=${port_range[0]}
  max_port_num=${port_range[1]}
  comm -23 <(seq ${min_port_num} ${max_port_num}) \
  <(ss -tan | awk '{print $4}' | cut -d':' -f2 | grep '[0-9]\{1,5\}' | sort | uniq) \
  | shuf | head -n 1
}

# return number of containers with $CONTAINER_PREFIX inside their names (default) or $1 inside their names.
# usage: container_count, container_count $PART_OF_THE_NAME
container_count() {
  local prefix=${1:-$CONTAINER_PREFIX}
  echo $(docker ps | grep $prefix | wc -l)
}

get_CONTAINER_NAME() {
  local prefix=${1:-$CONTAINER_PREFIX}
  local contianers

  if [[ ! $(hostname) == $REMOTE_HOST ]]; then
      containers=($(remote_exec docker ps | grep $prefix | awk '{print $NF}'))
  else
      containers=($(docker ps | grep $prefix | awk '{print $NF}'))
  fi

  if [[ "${#containers[@]}" == 0 ]]; then
      echo "no container found"
      return 1
  elif [[ "${#containers[@]}" == 1 ]]; then
      CONTAINER_NAME="${containers[0]}"
  elif [[ "${#containers[@]}" > 1 ]]; then
      local i=0
      for c in "${containers[@]}"; do
          echo "$i: $c"
          ((i=i+1))
      done
      local k
      [[ $i -eq 1 ]] && read -p "select [0]: " k
      [[ $i -gt 1 ]] && read -p "select container: " k

      [[ "$k" -lt 0 || "$k" -gt "$i" ]] && echo "invalid selection" && return 1
      CONTAINER_NAME="${containers[$k]}"
      echo "You selected: $CONTAINER_NAME"
      echo
  fi
}

declare -a PARAMS=()
_argv=()
for var in "$@" ; do
    if [[ "$var" =~ ^[a-z_]+=[^=]+$ ]]; then
        k="${var%=*}"
        v="${var#*=}"
        PARAMS[$k]=$v
    else
        _argv+=("$var")
    fi
done
set -- "${_argv[@]}"   # reassignment positional parameters
