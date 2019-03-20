#!/bin/bash
#####################################################################################################
#
# ABOUT THIS PROGRAM
#
# NAME
#   KeePassXCUpdate.sh
#
# DESCRIPTION 
#   Updates KeePassXC to latest version on Mac OS.
#   This script is provided as is, use at your own risk :)
#
# AUTHOR
#   https://github.com/pigeonpilot
#
# SYNOPSIS
#   sudo ./KeePassXCUpdate.sh
#
####################################################################################################

declare app_mount=""
declare curr_installed_app_ver=""
declare dmg_file=""
declare download_url=""
declare -r log_file="/Library/Logs/KeePassXCUpdate.log"
declare os_version=""
declare user_agent=""

set -u

trap cleanup_func 1 2 3 6 15

### START OF FUNCTION DECLARATIONS
logger_func () {
  /bin/echo "`/bin/date '+%Y-%m-%d %H:%M:%S'` `/usr/bin/basename "$0"` $1: $2" | /usr/bin/tee -a "${log_file}"
  if [ $1 = "ERROR" ]; then
    cleanup_func 1
  fi
}

cleanup_func () {
  umount_dmg_func
  delete_dmg_func
  logger_func INFO "End of script."
  if [ -z "${1}" ]; then
    exit 1
  else
    exit "${1}"
  fi
}

delete_dmg_func () {
  if [ -f "${dmg_file}" ] && [[ "${dmg_file}" =~ ^/tmp/.* ]]; then
    /bin/rm "${dmg_file}" > /dev/null 2>&1
    if [ ! $? -eq 0 ]; then
      logger_func WARN "Failed to delete installer image file ${dmg_file}."
    else
      logger_func INFO "Successfully deleted installer image."
    fi
  fi
}

umount_dmg_func () {
  if [ ! -z "${app_mount}" ]; then
    /usr/bin/hdiutil detach "${app_mount}" -quiet
    if [ ! $? -eq 0 ]; then
      logger_func WARN "Failed to unmount installer image."
    else
      logger_func INFO "Unmounting installer image."
    fi
  fi
}

app_ver_func () {
  curr_installed_app_ver=`defaults read "/Applications/KeePassXC.app/Contents/Info.plist" CFBundleShortVersionString`
  if [[ "${curr_installed_app_ver}" =~ ^[0-9]+ ]]; then
    download_url=`/usr/bin/curl --fail --connect-timeout 10 -m 300 -s -L -A "${user_agent}" "https://keepassxc.org/download/" | /usr/bin/sed -n 's/.*"\(https:\/\/github.com.*KeePassXC-.*.dmg\)">/\1/p'`
    if [ ! -z ${download_url} ]; then 
      latest_app_ver=`/bin/echo -n "${download_url}" | /usr/bin/sed -n 's/.*KeePassXC-\(.*\).dmg/\1/p'`
      if [[ ! "${latest_app_ver}" =~ ^[0-9]+ ]]; then
        logger_func ERROR "Error detecting latest version of KeePassXC."
      fi
    else
      logger_func INFO "Download URL is empty!"
    fi
  else
    logger_func ERROR "Error detecting installed version of KeePassXC."
  fi
}

update_func () {
  dmg_file="`/usr/bin/mktemp -q /tmp/XXXXXXXXXXXXXXXXXXXXXXXXX`"
  if [ $? -ne 0 ]; then
    logger_func ERROR "Can't create temp file, exiting..."
  fi

  logger_func INFO "Downloading update..."

  /usr/bin/curl -A "${user_agent}" --fail --connect-timeout 10 -m 300 -s -L -o "${dmg_file}" "${download_url}"
  if [ $? -eq 0 ]; then
    logger_func INFO "Successfully downloaded "${download_url}"."
  else
    logger_func ERROR "Error when downloading "${download_url}"."
  fi

  app_mount="`/usr/bin/hdiutil attach "${dmg_file}" -nobrowse | /usr/bin/tail -n1 | /usr/bin/cut -f 3`"
  if [ ! $? -eq 0 ]; then
    logger_func ERROR "Failed to mount the installer disk image."
  else
    logger_func INFO "Mounted the installer disk image at "${app_mount}"."
  fi

  /bin/rm -rf "/Applications/KeePassXC.app"
  if [ ! $? -eq 0 ]; then
    logger_func ERROR "Failed to delete applicationfolder."
  fi

  logger_func INFO "Installing update."

  /usr/bin/ditto -rsrc "${app_mount}/KeePassXC.app" "/Applications/KeePassXC.app" > /dev/null 2>&1
  if [ ! $? -eq 0 ]; then
    logger_func ERROR "Installation failed."
  fi

  newly_installed_ver=`defaults read "/Applications/KeePassXC.app/Contents/Info.plist" CFBundleShortVersionString`
  if [ "${latest_app_ver}" = "${newly_installed_ver}" ]; then
    logger_func INFO "KeePassXC has successfully been updated to version ${latest_app_ver}."
  else
    logger_func ERROR "KeePassXC update failed."
  fi
}
### END OF FUNCTION DECLARATIONS

logger_func INFO "Starting KeePassXCUpdate."

if [ '`/usr/bin/uname -p`'="i386" -o '`/usr/bin/uname -p`'="x86_64" ]; then
  os_version=$( /usr/bin/sw_vers -productVersion | /usr/bin/sed 's/[.]/_/g' )
  if [[ ! "${os_version}" =~ ^[0-9] ]]; then
    logger_func ERROR "Can't detect OS version."
  fi

  user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X ${os_version}) AppleWebKit/535.6.2 (KHTML, like Gecko) Version/5.2 Safari/535.6.2"
  
  app_ver_func

  if [ "${curr_installed_app_ver}" != "${latest_app_ver}" ]; then
    logger_func INFO "Installed version of KeePassXC is ${curr_installed_app_ver}, latest version is ${latest_app_ver}, update needed."
    update_func
  else
    logger_func INFO "Installed version of KeePassXC is ${curr_installed_app_ver}, latest version is ${latest_app_ver}, update is not needed."
  fi

  cleanup_func 0

else
  logger_func ERROR "This script is for Intel Macs only."
fi