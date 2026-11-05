#!/bin/bash
set -e

################################################################################
# Copy ssh keys from Windows
################################################################################
sudo apt-get update
sudo apt-get upgrade

################################################################################
# Install custom commands
################################################################################
bash ./linux/install_commands.sh

################################################################################
# Copy ssh keys from Windows
################################################################################
mkdir -p /home/$USER/.ssh
cp -r /mnt/c/Users/$USER/.ssh/. /home/$USER/.ssh/

################################################################################
# Setup ssh agent such that it always works with keys
################################################################################
sudo apt-get install -y keychain
shopt -s nullglob
sudo chmod 600 -R /home/$USER/.ssh
sudo chmod 700 /home/$USER/.ssh
keys=""
for p in /home/$USER/.ssh/*.pub; do
  k="${p%.pub}"
  [[ -f $k ]] || continue
  sudo chmod 600 "$k"; sudo chmod 644 "$p"
  keys+="$(basename "$k") "
done
if [[ -z $keys ]]; then
  echo "No .pub keys found in /home/$USER/.ssh: no keys will be added."
else
  read -rp "Add these keys to /home/$USER/.bashrc: ${keys}? [y/N] " ans
  if [[ $ans == [yY] ]]; then
    echo "eval \"\$(keychain --eval --quiet ${keys% })\"" >> /home/$USER/.bashrc
  else
    echo "No keys will be added."
  fi
fi

################################################################################
# Install basic dev tools
################################################################################
# Install uv for python
curl -LsSf https://astral.sh/uv/install.sh | bash

# Install the FFmpeg shared libraries. They are registered with ldconfig instead
# of LD_LIBRARY_PATH so that every process finds them, including scripts and
# non-interactive shells that never read .bashrc
sudo apt-get install -y xz-utils

FFMPEG_DIR=/opt/ffmpeg
FFMPEG_NAME=ffmpeg-n9.0-latest-linux64-gpl-shared-9.0
if [ ! -d "$FFMPEG_DIR" ]; then
  tmp="$(mktemp -d)"
  curl -LsSf "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/${FFMPEG_NAME}.tar.xz" \
    | tar xJ -C "$tmp"
  sudo chown -R root:root "$tmp/$FFMPEG_NAME"
  sudo mv "$tmp/$FFMPEG_NAME" "$FFMPEG_DIR"
  rm -rf "$tmp"
fi
echo "$FFMPEG_DIR/lib" | sudo tee /etc/ld.so.conf.d/ffmpeg.conf > /dev/null
sudo ldconfig
sudo ln -sf "$FFMPEG_DIR"/bin/* /usr/local/bin/

# Install rclone in /usr/local/bin so that it is on the PATH of every user and
# script
sudo apt-get install -y unzip

if ! command -v rclone > /dev/null; then
  tmp="$(mktemp -d)"
  curl -LsSf https://downloads.rclone.org/rclone-current-linux-amd64.zip -o "$tmp/rclone.zip"
  unzip -q "$tmp/rclone.zip" -d "$tmp"
  sudo install -D -m 755 "$tmp"/rclone-*-linux-amd64/rclone /usr/local/bin/rclone
  rm -rf "$tmp"
fi

################################################################################
# Install homebrew
################################################################################
sudo apt-get install -y ca-certificates \
    build-essential

/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
echo >> /home/$USER/.bashrc
echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"' >> /home/$USER/.bashrc
export PATH=/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:$PATH

################################################################################
# Install mutagen and mutagen watchdog to avoid failing for fail2ban
################################################################################
brew trust mutagen-io/mutagen
brew install mutagen-io/mutagen/mutagen

mkdir -p ~/.local/bin
mkdir -p ~/.config/systemd/user
cp ./linux/mutagen-watchdog.sh ~/.local/bin/mutagen-watchdog.sh
chmod +x ~/.local/bin/mutagen-watchdog.sh

cp ./linux/systemd/mutagen-watchdog.service ~/.config/systemd/user/mutagen-watchdog.service
if systemctl --user is-system-running >/dev/null 2>&1 || [ $? -eq 1 ]; then
  systemctl --user daemon-reload
  systemctl --user enable --now mutagen-watchdog
else
  echo "systemd not running: add '[boot]\nsystemd=true' to /etc/wsl.conf, run 'wsl --shutdown', then rerun."
fi

################################################################################
# Install singularity
################################################################################
sudo apt-get install -y \
   autoconf \
   automake \
   cryptsetup \
   fuse2fs \
   git \
   fuse3 \
   libfuse3-dev \
   libseccomp-dev \
   libtool \
   pkg-config \
   runc \
   squashfs-tools \
   squashfs-tools-ng \
   uidmap \
   wget \
   zlib1g-dev \
   zip

# Only from ubuntu 24.04 and newer
sudo apt-get install -y libsubid-dev

# Install Go as it is needed for singularity
export GO_VERSION=1.27.1 OS=linux ARCH=amd64

wget https://dl.google.com/go/go$GO_VERSION.$OS-$ARCH.tar.gz
# Extracting over an existing /usr/local/go produces a broken install
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzvf go$GO_VERSION.$OS-$ARCH.tar.gz
sudo rm go$GO_VERSION.$OS-$ARCH.tar.gz

# Add go to path for this script (sourcing /home/$USER/.bashrc is a no-op
# in non-interactive shells) and persist it for future shells
export PATH=/usr/local/go/bin:$PATH
grep -qxF 'export PATH=/usr/local/go/bin:$PATH' /home/$USER/.bashrc || \
   echo 'export PATH=/usr/local/go/bin:$PATH' >> /home/$USER/.bashrc

# Download singularity and install it
export VERSION=4.5.0

wget https://github.com/sylabs/singularity/releases/download/v${VERSION}/singularity-ce-${VERSION}.tar.gz
tar -xzf singularity-ce-${VERSION}.tar.gz
cd singularity-ce-${VERSION}

./mconfig
make -C builddir
sudo make -C builddir install
