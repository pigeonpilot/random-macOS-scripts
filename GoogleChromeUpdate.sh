#!/bin/bash
#####################################################################################################
#
# ABOUT THIS PROGRAM
#
# NAME
#   GoogleChromeUpdate.sh
#
# DESCRIPTION 
#   Updates Google Chrome to latest version on Mac OS.
#   This script is provided as is, use at your own risk :)
#
# AUTHOR
#   https://github.com/pigeonpilot
#
# SYNOPSIS
#   sudo ./GoogleChromeUpdate.sh
#
####################################################################################################

declare app_mount=""
declare current_ver=""
declare current_ver_norm=""
declare dmg_file=""
declare exit_status="1"
declare latest_ver=""
declare latest_ver_norm=""
declare -r log_file="/Library/Logs/GoogleChromeUpdateScript.log"
declare newly_installed_ver=""
declare os_version=""
declare user_agent=""

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

app_ver_func () {
  latest_ver=`/usr/bin/curl --fail --connect-timeout 10 -m 300 -s -L -A "${user_agent}" https://omahaproxy.appspot.com/history | /usr/bin/sed -n 's/^mac,stable,\(.*\),.*/\1/p' | /usr/bin/head -n1`
  if [[ "${latest_ver}" =~ ^[0-9]+ ]]; then
    latest_ver_norm=`/bin/echo "${latest_ver}" | /usr/bin/sed 's/[^0-9]//g'`
    if [ -e "/Applications/Google Chrome.app/Contents/Info.plist" ]; then
      current_ver=`/usr/bin/defaults read "/Applications/Google Chrome.app/Contents/Info.plist" CFBundleShortVersionString`
      if [[ ! "${current_ver}" =~ ^[0-9]+ ]]; then
        /logger_func ERROR "Cannot detect current version of Google Chrome."
      else
        current_ver_norm=`/bin/echo "${current_ver}" | /usr/bin/sed 's/[^0-9]//g'`
      fi
    else
      logger_func ERROR "Cannot find /Applications/Google Chrome.app/Contents/Info.plist."
    fi        
  else
    logger_func ERROR "Cannot detect latest update for Google Chrome."
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

update_func () {
  dmg_file="`/usr/bin/mktemp -q /tmp/XXXXXXXXXXXXXXXXXXXXXXXXX`"
  if [ $? -ne 0 ]; then
    logger_func ERROR "Can't create temp file, exiting..."
  fi
  
  logger_func INFO "Downloading update..."

  /usr/bin/curl -A "${user_agent}" --fail --connect-timeout 10 -m 300 -s -o "${dmg_file}" "https://dl.google.com/chrome/mac/stable/GGRO/googlechrome.dmg"
  if [ $? -eq 0 ]; then
    logger_func INFO "Successfully downloaded https://dl.google.com/chrome/mac/stable/GGRO/googlechrome.dmg."
  else
    logger_func ERROR "Error when downloading https://dl.google.com/chrome/mac/stable/GGRO/googlechrome.dmg."
  fi

  app_mount="`/usr/bin/hdiutil attach "${dmg_file}" -nobrowse | /usr/bin/tail -n1 | /usr/bin/cut -f 3`"
  if [ ! $? -eq 0 ]; then
    logger_func ERROR "Failed to mount the installer disk image."
  else
    logger_func INFO "Mounted the installer disk image at ${app_mount}."
  fi

  /bin/rm -rf "/Applications/Google Chrome.app"
  if [ ! $? -eq 0 ]; then
    logger_func ERROR "Failed to delete applicationfolder."
  fi

  logger_func INFO "Installing."

  /usr/bin/ditto -rsrc "${app_mount}/Google Chrome.app" "/Applications/Google Chrome.app" > /dev/null 2>&1
  if [ ! $? -eq 0 ]; then
    logger_func ERROR "Installation failed."
  fi

  newly_installed_ver=`/usr/bin/defaults read "/Applications/Google Chrome.app/Contents/Info.plist" CFBundleShortVersionString`
  if [ "${latest_ver}" = "${newly_installed_ver}" ]; then
    logger_func INFO "Google Chrome has successfully been updated to version "${latest_ver}"."
  else
    logger_func ERROR "Google Chrome update failed."
  fi

}
### END OF FUNCTION DECLARATIONS

logger_func INFO "Starting GoogleChromeUpdate."

if [ '`/usr/bin/uname -p`'="i386" -o '`/usr/bin/uname -p`'="x86_64" ]; then

os_version=$( /usr/bin/sw_vers -productVersion | /usr/bin/sed 's/[.]/_/g' )
if [[ ! "${os_version}" =~ ^[0-9] ]]; then
  logger_func ERROR "Can't detect OS version"
fi

user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X ${os_version}) AppleWebKit/535.6.2 (KHTML, like Gecko) Version/5.2 Safari/535.6.2"

app_ver_func

if [ "${current_ver_norm}" != "${latest_ver_norm}" ]; then
  logger_func INFO "Installed version of Google Chrome is ${current_ver}, latest version is ${latest_ver}, update needed."
  update_func
else
  logger_func INFO "Installed version of Google Chrome is ${current_ver}, latest version is ${latest_ver}, update is not needed."
  cleanup_func 0
fi

cleanup_func 0

else
  logger_func ERROR "This script is for Intel Macs only."
fi