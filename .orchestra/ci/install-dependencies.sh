#!/bin/bash

set -e

export DEBIAN_FRONTEND=noninteractive

# Temporary workaround
# packagecloud.io is refusing to serve git-lfs packages
rm -f /etc/apt/sources.list.d/github_git-lfs.list &> /dev/null

apt-get -qq update

apt-get -qq install --no-install-recommends --yes \
  aufs-tools \
  autoconf \
  automake \
  bison \
  build-essential \
  ca-certificates \
  cmake \
  curl \
  doxygen \
  flex \
  g++-multilib \
  gawk \
  git \
  graphviz \
  graphviz-dev \
  jq \
  libc-dev \
  libexpat1-dev \
  libglib2.0-dev \
  liblzma-dev \
  libncurses5-dev \
  libreadline-dev \
  libtool \
  m4 \
  ninja-build \
  pkg-config \
  python \
  python3 \
  python3-pip \
  python3-dev \
  python3-cffi \
  python3-setuptools \
  rsync \
  sed \
  ssh \
  texinfo \
  valgrind \
  wget \
  zlib1g-dev

# Dependencies for Qt
apt-get -qq install --no-install-recommends --yes \
  gperf \
  libcap-dev \
  libfontconfig1-dev \
  libfreetype6-dev \
  libgl-dev \
  libgl1-mesa-dev \
  libgles2-mesa-dev \
  libinput-dev \
  libmount-dev \
  libssl-dev \
  libx11-dev \
  libx11-xcb-dev \
  libxcb-glx0-dev \
  libxcb1-dev \
  libxext-dev \
  libxfixes-dev \
  libxi-dev \
  libxkbcommon-dev \
  libxkbcommon-x11-dev \
  libxrender-dev

pip3 -q install --user --upgrade setuptools wheel mako meson==0.56.2 pyelftools pygraphviz==1.6

if ! which git-lfs &> /dev/null; then
  LFS_ARCHIVE_URL="https://github.com/git-lfs/git-lfs/releases/download/v2.13.3/git-lfs-linux-amd64-v2.13.3.tar.gz"
  wget -o /tmp/git-lfs.tar.gz "$LFS_ARCHIVE_URL"
  mkdir -p /tmp/lfs-install
  pushd /tmp/lfs-install &>/dev/null
  tar xf /tmp/git-lfs.tar.gz
  /tmp/lfs-install/install.sh
  popd
fi

# Ensure git-lfs is available
if ! which git-lfs &> /dev/null; then
  exit 1
fi
