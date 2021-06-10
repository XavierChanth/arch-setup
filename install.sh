#!/bin/bash
# NOTE: THIS SCRIPT WILL REPLACE YOUR BASHRC WITH THE ORIGINAL

full_path="$(pwd)/${BASH_SOURCE}"
dir_path="${full_path%/*}"
source "$dir_path/config.sh"

exit_command() {
  unset $PASSWORD
  unset $HISTIGNORE
  [[ "$0" = "$BASH_SOURCE" ]] && exit 1 || return 1;
}

pre_install_prompts() {
  # force main function to run with sudo
  if [ "$EUID" -eq 0 ]
  then
    echo 'This script will prompt you for your credentials, please do not run as sudo'
    exit_command
  fi

  # prompt that config is setup
  read -p "Did you setup your details in the config.sh file? [Y/n]: " -n 1 REPLY
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]
  then
    echo 'Exiting now'
    exit_command
  fi

  # prompt git config
  if [[ -z $git_user_name ]]
  then
    read -p 'git username: ' -r
    export git_user_name=$REPLY
  fi

  if [[ -z $git_user_email ]]
  then
    read -p 'git email: ' -r
    export git_user_email=$REPLY
  fi

  if [[ -z $git_credential_helper ]]
  then
    read -p 'git credential helper: ' -r
    export git_credential_helper=$REPLY
  fi
}

pre_install() {
  mkdir -p $HOME/.arch-setup-pkgs
  FILE=$dir_path/bashrc.bak
  if [ ! -f "$FILE" ]; then
    cp $HOME/.bashrc $FILE
  fi

  echo y | cp /etc/skel/.bashrc $HOME

  # IGNORE SUDO COMMANDS TO PROTECT PASSWORD
  export HISTIGNORE='*sudo -S*'
  # GET sudo password
  read -p "sudo password: " -s -r
  export PASSWORD=$REPLY
  echo
  # Reset user auth
  sudo -k

  # Test user auth
  if sudo -lS &>/dev/null <<< "$PASSWORD";
  then
    echo 'Password accepted'
  else
    echo 'Failed to authenticate'
    exit_command
  fi
  sudo -k
}

auth_user() {
  sudo -Sv <<< $PASSWORD
}

run_root() {
  echo $PASSWORD | sudo -S $*
}

make_pacman() {
  auth_user
  echo yes | sudo pacman -S $*
}

make_aur() {
  auth_user
  cd $HOME/.arch-setup-pkgs
  run_root rm -rf $1
  git clone "https://aur.archlinux.org/$1"
  cd $1
  echo yes | makepkg -si
  cd ..
  run_root rm -rf $1
  cd $dir_path
}

setup_linux() {
  run_root pacman -Syu
  run_root pacman -S --needed base-devel
  run_root pacman -S --needed $packages
}

setup_paru() {
  # build paru from the aur
  make_aur paru.git
  # enable color in paru
  sudo sed -e ':a' -e 'N' -e '$!ba' -e 's/\n#Color\n/\nColor\n/g';
  # enable bottomup in paru
  sudo sed -e ':a' -e 'N' -e '$!ba' -e 's/\n#BottomUp\n/\nBottomUp\n/g';
}

setup_git() {
  ssh_file_name="$HOME/.ssh/id_$ssh_keygen_type"

  # git global config -- make sure to set variables in config.sh
  git config --global user.name $git_user_name
  git config --global user.email $git_user_email
  git config --global credential.helper $git_credential_helper
  #pretty log statements
  git config --global alias.lg "lg1"
  git config --global alias.lg1 "lg1-specific --all"
  git config --global alias.lg2 "lg2-specific --all"
  git config --global alias.lg3 "lg3-specific --all"
  git config --global alias.lg1-specific "log --graph --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) - %C(bold green)(%ar)%C(reset) %C(white)%s%C(reset) %C(dim white)- %an%C(reset)%C(auto)%d%C(reset)'"
  git config --global alias.lg2-specific "log --graph --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) - %C(bold cyan)%aD%C(reset) %C(bold green)(%ar)%C(reset)%C(auto)%d%C(reset)%n''          %C(white)%s%C(reset) %C(dim white)- %an%C(reset)'"
  git config --global alias.lg3-specific "log --graph --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) - %C(bold cyan)%aD%C(reset) %C(bold green)(%ar)%C(reset) %C(bold cyan)(committed: %cD)%C(reset) %C(auto)%d%C(reset)%n''          %C(white)%s%C(reset)%n''          %C(dim white)- %an <%ae> %C(reset) %C(dim white)(committer: %cn <%ce>)%C(reset)'"

  # add git key to the ssh agent
  echo $ssh_file_name | ssh-keygen -t $ssh_keygen_type -C "$git_user_email"
  eval "$(ssh-agent -s)"
  ssh-add $ssh_file_name
}

setup_bashrc() {
  # Add Fetchmaster6000
  curl https://raw.githubusercontent.com/anhsirk0/fetch-master-6000/master/fm6000.pl -o ./fm6000
  chmod +x fm6000
  mkdir -p $HOME/.local/bin
  echo yes | mv fm6000 $HOME/.local/bin/fm6000

  BASH_FILE_LOCATION="$HOME/.bashrc"

  # Change the default PS1 color prompt
  PS1_color_pattern="PS1='\\[\\.*\$"
  PS1_color_prompt="PS1='\\[\$(tput bold)\\]\\e[;35m\\u\\e[m \\e[;34m[\\e[;36m\\w\\e[;34m]\\e[m \\e[;35m>\\e[m \\[\$(tput sgr0)\\]'"
  sed -i "s/$PS1_color_pattern/$PS1_color_prompt/g" $BASH_FILE_LOCATION

  # Add some useful aliases to bashrc
  echo $'
# LS ALIASES
alias ll=\'ls -alF\'
alias la=\'la -A\'
alias l=\'ls -CF\'

# FM 6000 SETTINGS
alias fm6000=\'fm6000 -m 8 -g 8 -l 21 -c magenta -s "bash $(echo $BASH_VERSION | cut -d- -f1)"\'
alias clear=\'clear && fm6000\'

# QUICK CALENDAR
alias jan=\'cal -m 01\'
alias feb=\'cal -m 02\'
alias mar=\'cal -m 03\'
alias apr=\'cal -m 04\'
alias may=\'cal -m 05\'
alias jun=\'cal -m 06\'
alias jul=\'cal -m 07\'
alias aug=\'cal -m 08\'
alias sep=\'cal -m 09\'
alias oct=\'cal -m 10\'
alias nov=\'cal -m 11\'
alias dec=\'cal -m 12\'
color_prompt=
if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
    color_prompt=yes
fi

if [ "$color_prompt" = yes ]; then
    PS1=\'\[$(tput bold)\]\\e[;35m\u\\e[m \\e[;34m[\\e[;36m\w\\e[;34m]\\e[m \\e[;35m>\\e[m \[$(tput sgr0)\]\'
fi
unset color_prompt
echo -e "\\e[;35m                Welcome $USER\\n                $(date +\'%a %b %d %Y | %R\')$(fm6000)\\e[m\\n"
' >> $BASH_FILE_LOCATION
}

setup_fonts() {
  make_pacman $arch_fonts
  font_packages=$(echo $aur_fonts | tr ";" "\n")
  for font_package in $font_package
  do
    make_aur $font_package
  done
}

setup_apps() {
  make_pacman $arch_apps
  app_packages=$(echo $aur_apps | tr ";" "\n")
  for app_package in $app_packages
  do
    make_aur $app_package
  done
}

setup_flutter() {
  make_pacman "jdk8-openjdk"
  # Add JAVA_HOME AND PATH to bashrc
  echo -e '\nexport JAVA_HOME="/usr/lib/jvm/java-8-openjdk"\nexport PATH=$JAVA_HOME/bin:$PATH' >> $HOME/.bashrc

  cd $HOME/.local/bin
  git clone https://github.com/flutter/flutter.git -b stable
  echo -e '\nexport PATH=$HOME/.local/bin/flutter/bin:$PATH' >> $HOME/.bashrc
  cd $dir_path

  android_packages="android-sdk android-sdk-platform-tools android-sdk-build-tools"
  for android_package in $android_packages
  do
    make_aur $android_package
  done
  make_aur "android-platform"

  ANDROID_SDK_ROOT='/opt/android-sdk'

  # permissions for android-sdk
  run_root groupadd android-sdk
  run_root gpasswd -a $USER android-sdk
  run_root chmod -R 777 $ANDROID_SDK_ROOT
  run_root chown -R $USER:android-sdk $ANDROID_SDK_ROOT

  # bashrc
  echo -e "\n
export ANDROID_HOME=$HOME/.android
export ANDROID_SDK_ROOT=$ANDROID_SDK_ROOT
export PATH=\$PATH:\$ANDROID_SDK_ROOT/platform-tools
export PATH=\$PATH:\$ANDROID_SDK_ROOT/emulator
export PATH=\$PATH:\$ANDROID_SDK_ROOT/tools
export PATH=\$PATH:\$ANDROID_SDK_ROOT/tools/bin
" >> "$HOME/.bashrc"

  yes | sdkmanager --licenses
  echo yes | sdkmanager --install $android_image
  echo no | avdmanager create avd -n "my-avd" -k $android_image
}

setup_node() {
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.38.0/install.sh | bash

  echo '
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
' >> $HOME/.bashrc

  export NVM_DIR="$HOME/.nvm"
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

  nvm install --lts
  nvm use --lts

  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  packages="yarn eslint typescript"
  npm i -g $packages
}

setup_docker() {
  make_pacman docker docker-compose

  run_root systemctl start docker.service
  run_root systemctl enable docker.service

  run_root groupadd docker
  run_root gpasswd -a $USER docker
}

setup_ve() {
  mkdir -p $HOME/@ve
  curl -L atsign.dev/curl/virtualenv-compose-vip.yaml -o $HOME/@ve/docker-compose.yaml;
  echo "docker-compose down && docker-compose pull && docker-compose up -d" > $HOME/@ve/update.sh;

  run_root cp $dir_path/ve-loopback-alias.network /etc/systemd/network/loopback-alias.network

  run_root systemctl enable systemd-networkd.service
  run_root systemctl restart systemd-networkd.service
  cd $HOME/@ve
  docker-compose up -d
  cd $dir_path
}

post_install() {
  source $HOME/.bashrc
  echo;echo "############################";echo;
  echo 'POST INSTALL STEPS:';echo;

  echo '1. Add your ssh key to github:';
  echo '    xclip -selection clipboard < $ssh_file.pub';echo;

  echo '2. Run flutter doctor and flutter doctor --android-licenses'

  exit_command
}

main() {
  pre_install_prompts
  pre_install

  #setup_linux
  #setup_paru
  setup_git
  setup_bashrc
  setup_fonts
  setup_apps
  setup_flutter
  setup_node
  setup_docker
  setup_ve

  post_install
}

# start the main function
main
