#!/bin/bash
cd "${BASH_SOURCE%/*}";

exit_command() {
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

  if [[ ! $REPLY =~ ^[Yy]$ ]]
  then
    echo 'Exiting now'
    exit_command
  fi
}

auth_user() {
  echo $PASSWORD | sudo -Sn true
}

pre_install() {
  # IGNORE SUDO COMMANDS TO PROTECT PASSWORD
  export HISTIGNORE='*sudo -S*'

  # GET sudo password
  read -p "sudo password: " -s PASSWORD
  # Reset user auth
  sudo -k
  # Try to auth user
  auth_user
  # Get the results for auth sucess
  auth_check="$(sudo -vn)"
  if [[ ! -z $auth_check ]]
  then
    echo 'Failed to authenticate'
    exit_command
  fi

  source config.sh
}

run_root() {
  echo $PASSWORD | sudo -S  $*
}

make_pacman() {
  auth_user
  echo yes | pacman -S $*
}

make_aur() {
  auth_user
  git clone "https://aur.archlinux.org/$1"
  cd $1
  makepkg -si
  cd ..
  rm -r $1
}

setup_linux() {
  pacman -Syu
  pacman -S --needed base-devel
  pacman -S $packages
}

setup_paru() {
  # build paru from the aur
  make_aur paru
  # enable color in paru
  sudo sed -e ':a' -e 'N' -e '$!ba' -e 's/\n#Color\n/\nColor\n/g';
  # enable bottomup in paru
  sudo sed -e ':a' -e 'N' -e '$!ba' -e 's/\n#BottomUp\n/\nBottomUp\n/g';
}

setup_git() {
  ssh_file_name="id_$ssh_keygen_type"

  # git global config -- make sure to set variables in config.sh
  git config --global user.name $git_user_name
  git config --global user.email $git_user_email
  git config --global credential.helper $git_credential_helper

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
  mv fm6000 $HOME/.local/bin/fm6000

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

  flutter_packages="flutter android-sdk android-sdk-platform-tools android-sdk-build-tools"
  for flutter_package in $flutter_packages
  do
    make_aur $flutter_package
  done
  make_aur "android-platform"

  # permissions for flutter
  run_root groupadd flutterusers
  run_root gpasswd -a $USER flutterusers
  run_root chown -R :flutterusers /opt/flutter
  run_root chmod -R g+w /opt/flutter/

  flutter upgrade

  # permissions for android-sdk
  run_root groupadd android-sdk
  run_root gpasswd -a $USER android-sdk
  run_root setfacl -R -m g:android-sdk:rwx /opt/android-sdk
  run_root setfacl -d -m g:android-sdk:rwx /opt/android-sdk

  ANDROID_SDK_ROOT='/opt/android-sdk'

  # bashrc
  echo -e "\n
  export ANDROID_HOME=$HOME/.android
  export ANDROID_SDK_ROOT=$ANDROID_SDK_ROOT
  export PATH=\$PATH:\$ANDROID_SDK_ROOT/platform-tools
  export PATH=\$PATH:\$ANDROID_SDK_ROOT/emulator
  export PATH=\$PATH:\$ANDROID_SDK_ROOT/tools
  export PATH=\$PATH:\$ANDROID_SDK_ROOT/tools/bin
  " >> "$HOME/.bashrc"

  sudo chown -R $(whoami) $ANDROID_SDK_ROOT

  echo yes | sdkmanager --install $android_image
  echo no | avdmanager create avd -n "my-avd" -k $android_image
}

setup_node() {
  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.38.0/install.sh | bash

  nvm install --lts
  nvm use --lts

  packages="yarn eslint typescript"

  source $HOME/.nvm/nvm.sh
  npm i -g $packages
}

setup_docker() {
  make_pacman docker docker-compose

  root_run systemctl start docker.service
  root_run systemctl enable docker.service

  root_run groupadd docker
  root_run gpasswd -a $USER docker
}

setup_ve() {
  mkdir -p $HOME/@ve
  curl -L atsign.dev/curl/virtualenv-compose-vip.yaml -o $HOME/@ve/docker-compose.yaml;
  echo "docker-compose down && docker-compose pull && docker-compose up -d" > $HOME/@ve/update.sh;

  run_root echo '
[Match]
Name=lo

[Network]

[Address]
Label=lo
Address=10.64.64.64/32
Address=127.0.0.1/8

[Route]
EOF
' > /etc/systemd/network/loopback-alias.network

  run_root systemctl enable systemd-networkd.service
  run_root systemctl restart systemd-networkd.service

  docker-compose up -f $HOME/@ve -d
}

post_install() {
  unset $PASSWORD
  unset $HISTIGNORE
  source $HOME/.bashrc
  echo;echo "############################";echo;
  echo 'POST INSTALL STEPS:';echo;

  echo '1. Add your ssh key to github:';
  echo '    xclip -selection clipboard < $ssh_file.pub';echo;


}

main() {
  pre_install_prompts
  pre_install

  setup_linux
  setup_paru
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
main $*
