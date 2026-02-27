#!/bin/bash

update_config() {
  if [ "$#" -ne 3 ]; then
      echo "update_config requires 3 arguments"
      return 1
  fi
  sed -i "s;$2=.*;$2=$3;" $1
}

uncomment_config() {
  if [ "$#" -ne 3 ]; then
      echo "uncomment_config requires 3 arguments"
      return 1
  fi
  sed -i "s;#$2.*;$2 $3;" $1
}

enable_plugin() {
  if [ "$#" -eq 2 ]; then
      plugin_name=$2
  elif [ "$#" -eq 3 ]; then
      plugin_name=$3
  else
      echo "enable_plugin requires 2 or 3 arguments"
      return 1
  fi
  sed -i "s;#set -g @plugin '$2';set -g @plugin '$plugin_name';" $1
}


install_tmux() {
  TMUX_DL_LOCATION="https://github.com/tmux/tmux-builds/releases/download/"
  TMUX_TAG="v3.6a"
  TMUX_FILE="tmux-3.6a-linux-x86_64.tar.gz"
  TMUX_SHA256="c0a772a5e6ca8f129b0111d10029a52e02bcbc8352d5a8c0d3de8466a1e59c2e"
  
  echo "Downloading tmux release ${TMUX_TAG}"
  cd
  wget -q ${TMUX_DL_LOCATION}${TMUX_TAG}/${TMUX_FILE}
  if echo "${TMUX_SHA256}  ${TMUX_FILE}" | sha256sum -c; then
    tar -xzf ${TMUX_FILE} -C bin
    echo "Tmux release downloaded successfully, verifying binary"
    if bin/tmux -V; then
      echo "Binary ran successfully"
      install_oh_my_tmux
    fi
  else
    echo "Downloaded tmux release failed checksum verification, skipping tmux setup."
  fi
  rm -f ${TMUX_FILE}
}

install_oh_my_tmux() {
  echo "Installing tmux configuration"

  echo "Preparing home directory"
  cd
  if [ -d ".tmux" ]; then
    echo "Found existing .tmux dir, backing up to .tmux.bak"
    mv ".tmux" ".tmux.bak"
  fi

  for conf_file in ".tmux.conf" ".tmux.conf.local"; do
    if [ -f "$conf_file" ]; then
      if [ -L "$conf_file" ]; then
        echo "Found existing symlink for $conf_file - removing"
        rm "$conf_file"
      else
        echo "Found existing file $conf_file - backing up to ${conf_file}.bak"
        mv "$conf_file" "${conf_file}.bak"
      fi
    fi
  done

  echo "Cloning base configuration"
  mkdir -p .tmux/config
  git clone -q --single-branch https://github.com/gpakosz/.tmux.git .tmux/config

  echo "Creating symlink to main config and copying base local config"
  ln -s -f .tmux/config/.tmux.conf
  cp .tmux/config/.tmux.conf.local .
}

apply_nick_config() {
  cd
  echo "Customising tmux configuration"
  update_config .tmux.conf.local "tmux_conf_new_session_prompt" "true"
  update_config .tmux.conf.local "tmux_conf_theme_terminal_title" '"#h #W"'
  update_config .tmux.conf.local "tmux_conf_copy_to_os_clipboard" "true"
  uncomment_config .tmux.conf.local "set -g history-limit" "50000"
  uncomment_config .tmux.conf.local "set -g mouse" "on"
  uncomment_config .tmux.conf.local "set -g status-position" "top"
  enable_plugin .tmux.conf.local "tmux-plugins/tmux-copycat"
  enable_plugin .tmux.conf.local "tmux-plugins/tmux-cpu"
  enable_plugin .tmux.conf.local "tmux-plugins/tmux-resurrect" "nickusve/tmux-resurrect"
  enable_plugin .tmux.conf.local "tmux-plugins/tmux-continuum"
  uncomment_config .tmux.conf.local "set -g @continuum-restore" "'on'"

  # Custom keybinds
  awk '1; /# -- user customizations ---.*/{print "\n# Custom keybinds\nbind -n S-Left  previous-window\nbind -n S-Right next-window\nbind -n C-S-Left swap-window -d -t -1\nbind n C-S-Right swap-window -d -t +1"}' .tmux.conf.local > .tmux.conf.local.tmp && mv .tmux.conf.local.tmp .tmux.conf.local
}

cd
install_tmux
apply_nick_config

# Create a session to cause plugins to install
~/bin/tmux new-session -d -s init

# Wait for it to finish
timeout=15
while : ; do
  if [ -f .tmux/plugins/tpm_log.txt ]; then
    if cat .tmux/plugins/tpm_log.txt | grep -q "Done."; then
      echo "Tmux plugins installed"
      break
    else
      echo "Waiting for tmux plugins to install..."
      sleep 1
    fi
  else
    echo "Waiting for tmux plugin install to start..."
  fi
  sleep 1
  timeout=$((timeout - 1))
  if [ $timeout -le 0 ]; then
    echo "Timeout waiting for tmux plugin installation"
    break
  fi
done

echo "Killing init tmux session"
~/bin/tmux kill-session -t init

echo "Cloning home dir repo to finish setup"
cd
git clone -q --single-branch https://github.com/nickusve/home_dir.git setup_tmp

home_dir_path=$(realpath setup_tmp)

# User service for SSH agent
mkdir -p ~/.config/systemd/user
cp $home_dir_path/ssh-agent.service ~/.config/systemd/user/

# Start service and enable on boot
systemctl --user enable ssh-agent
systemctl --user start ssh-agent

cat $home_dir_path/.nick.bashrc >> ~/.bashrc
cp $home_dir_path/.nick_alias ~/

# Add bin and lib dirs in home for local programs and libraries
mkdir -p bin lib
cp -r $home_dir_path/tmux_helpers ~/

rm -rf setup_tmp
