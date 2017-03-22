#!/usr/bin/env bash
# bin/compile <build-dir> <cache-dir>

# fail fast
set -e

if [ $STACK != "cedar-14" ]; then
	echo "Stack ${STACK} not supported" && exit 1
fi

BUILD_DIR=$1
CACHE_DIR=$2
ENV_DIR=$3

function print() {
  echo "-----> $*"
}

function indent() {
  c='s/^/       /'
  case $(uname) in
    Darwin) sed -l "$c";;
    *)      sed -u "$c";;
  esac
}

function export_env_dir() {
  local env_dir=$1
  local whitelist_regex=${2:-'(CORE_VERSION|PROJECT|BUILD_DEBUG|CORE_BRANCH|CORE_REL_VERSION)$'}
  local blacklist_regex=${3:-'^(PATH|GIT_DIR|CPATH|CPPATH|LD_PRELOAD|LIBRARY_PATH)$'}
  if [ -d "$env_dir" ]; then
    for e in $(ls $env_dir); do
      echo "$e" | grep -E "$whitelist_regex" | grep -qvE "$blacklist_regex" &&
      export "$e=$(cat $env_dir/$e)"
      :
    done
  fi
}

LD_DIR=`cd $(dirname $0); cd ..; pwd`
export_env_dir ${ENV_DIR}

# Create Cache Directory
mkdir -p ${CACHE_DIR}
APT_CACHE_DIR="$CACHE_DIR/apt/cache"
APT_STATE_DIR="$CACHE_DIR/apt/state"
mkdir -p "$APT_CACHE_DIR/archives/partial"
mkdir -p "$APT_STATE_DIR/lists/partial"
APT_OPTIONS="-o debug::nolocking=true -o dir::cache=$APT_CACHE_DIR -o dir::state=$APT_STATE_DIR"
print "Updating apt caches"
apt-get $APT_OPTIONS update | indent

SQL_DWLD_URL="https://packages.microsoft.com/ubuntu/16.04/mssql-server/pool/main/m/mssql-server/mssql-server_14.0.304.138-1_amd64.deb"
apt-key adv --fetch-keys http://packages.microsoft.com/keys/microsoft.asc
mkdir -p ${BUILD_DIR}/.apt
wget ${SQL_DWLD_URL} -qO ${LD_DIR}/lib

for DEB in $(ls -1 $LD_DIR/lib/*.deb); do
  print "Installing $(basename $DEB)"
  dpkg -x $DEB ${BUILD_DIR}/.apt/
done

export PATH="${BUILD_DIR}/.apt/usr/bin:$PATH"
export LD_LIBRARY_PATH="${BUILD_DIR}/.apt/usr/lib/x86_64-linux-gnu:${BUILD_DIR}/.apt/usr/lib/i386-linux-gnu:${BUILD_DIR}/.apt/usr/lib:$LD_LIBRARY_PATH"
export LIBRARY_PATH="${BUILD_DIR}/.apt/usr/lib/x86_64-linux-gnu:${BUILD_DIR}/.apt/usr/lib/i386-linux-gnu:${BUILD_DIR}/.apt/usr/lib:$LIBRARY_PATH"
export INCLUDE_PATH="${BUILD_DIR}/.apt/usr/include:$INCLUDE_PATH"
export CPATH="$INCLUDE_PATH"
export CPPPATH="$INCLUDE_PATH"
export PKG_CONFIG_PATH="${BUILD_DIR}/.apt/usr/lib/x86_64-linux-gnu/pkgconfig:${BUILD_DIR}/.apt/usr/lib/i386-linux-gnu/pkgconfig:${BUILD_DIR}/.apt/usr/lib/pkgconfig:$PKG_CONFIG_PATH"
export | grep -E -e ' (PATH|LD_LIBRARY_PATH|LIBRARY_PATH|INCLUDE_PATH|CPATH|CPPPATH|PKG_CONFIG_PATH)='  > "$LD_DIR/export"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH}"

mkdir -p ${BUILD_DIR}/.profile.d
cat <<EOF >${BUILD_DIR}/.profile.d/000_apt.sh
export PATH="$HOME/.apt/usr/bin:$PATH"
export LD_LIBRARY_PATH="\$HOME/.apt/usr/lib/x86_64-linux-gnu:\$HOME/.apt/usr/lib/i386-linux-gnu:\$HOME/.apt/usr/lib:\$LD_LIBRARY_PATH"
export LIBRARY_PATH="\$HOME/.apt/usr/lib/x86_64-linux-gnu:\$HOME/.apt/usr/lib/i386-linux-gnu:\$HOME/.apt/usr/lib:\$LIBRARY_PATH"
export INCLUDE_PATH="\$HOME/.apt/usr/include:\$INCLUDE_PATH"
export CPATH="\$INCLUDE_PATH"
export CPPPATH="\$INCLUDE_PATH"
export PKG_CONFIG_PATH="\$HOME/.apt/usr/lib/x86_64-linux-gnu/pkgconfig:\$HOME/.apt/usr/lib/i386-linux-gnu/pkgconfig:\$HOME/.apt/usr/lib/pkgconfig:\$PKG_CONFIG_PATH"
EOF

print "Procfile setting"
cat <<EOF >${BUILD_DIR}/Procfile
web: ${HOME}/.apt/opt/mssql/bin/mssqlserv.sh
EOF
