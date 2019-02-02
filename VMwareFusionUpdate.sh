#!/bin/bash
#####################################################################################################
#
# ABOUT THIS PROGRAM
#
# NAME
#   VMwareFusionUpdate.sh
#
# DESCRIPTION 
#   Updates minor versions for VMware Fusion on Mac OS.
#   This script is provided as is, use at your own risk :)
#
# AUTHOR
#   https://github.com/pigeonpilot
#
# SYNOPSIS
#   sudo ./VMwareFusionUpdate.sh
#
####################################################################################################

declare app_mount=""
declare curr_installed_app_build=""
declare curr_installed_app_ver=""
declare curr_installed_app_major=""
declare dmg_file=""
declare -r download_url="https://download3.vmware.com/software/fusion/file"
declare latest_app_build=""
declare latest_app_ver=""
declare -r log_file="/Library/Logs/VMwareFusionUpdate.log"
declare os_version=""
declare -r update_url="https://softwareupdate.vmware.com/cds/vmw-desktop/fusion"
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
  curr_installed_app_ver=`/usr/bin/defaults read "/Applications/VMware Fusion.app/Contents/Info.plist" CFBundleShortVersionString`
  curr_installed_app_build=`/usr/bin/defaults read "/Applications/VMware Fusion.app/Contents/Info.plist" CFBundleVersion`
  if [[ "${curr_installed_app_ver}" =~ ^[0-9]+ ]] && [[ "${curr_installed_app_build}" =~ ^[0-9]+ ]]; then
    curr_installed_app_major=`/bin/echo $curr_installed_app_ver | /usr/bin/cut -d "." -f 1`
  else
    logger_func ERROR "Error detecting installed version of VMware Fusion."
  fi

  latest_app_ver=`/usr/bin/curl --fail --connect-timeout 10 -m 300 -s -L -A "${user_agent}" "${update_url}" | /usr/bin/sed -n 's/.*href="\(.*\)\/".*/\1/p' | /usr/bin/grep ^"${curr_installed_app_major}" | /usr/bin/sort -n | /usr/bin/tail -n 1`
  if [[ "${latest_app_ver}" =~ ^[0-9]+ ]]; then
    latest_app_build=`/usr/bin/curl --fail --connect-timeout 10 -m 300 -s -L -A "${user_agent}" "${update_url}/${latest_app_ver}" | /usr/bin/sed -n 's/.*href="\([0-9]*\)\/".*/\1/p'`
  else
    logger_func ERROR "Error detecting latest version of VMware Fusion."
  fi
}

update_func () {
  dmg_file="`/usr/bin/mktemp -q /tmp/XXXXXXXXXXXXXXXXXXXXXXXXX`"
  if [ $? -ne 0 ]; then
    logger_func ERROR "Can't create temp file, exiting..."
  fi
  
  logger_func INFO "Downloading update..."
  
  /usr/bin/curl -A "${user_agent}" --fail --connect-timeout 10 -m 300 -s -o "${dmg_file}" "${download_url}/VMware-Fusion-${latest_app_ver}-${latest_app_build}.dmg"
  if [ $? -eq 0 ]; then
    logger_func INFO "Successfully downloaded ${download_url}/VMware-Fusion-${latest_app_ver}-${latest_app_build}.dmg."
  else
    logger_func ERROR "Error when downloading ${download_url}/VMware-Fusion-${latest_app_ver}-${latest_app_build}.dmg."
  fi

  app_mount="`/usr/bin/hdiutil attach "${dmg_file}" -nobrowse | /usr/bin/tail -n1 | /usr/bin/cut -f 3`"
  if [ ! $? -eq 0 ]; then
    logger_func ERROR "Failed to mount the installer disk image."
  else
    logger_func INFO "Mounted the installer disk image at "${app_mount}"."
  fi

  /bin/rm -rf "/Applications/VMware Fusion.app"
  if [ ! $? -eq 0 ]; then
    logger_func ERROR "Failed to delete applicationfolder."
  fi

  logger_func INFO "Installing update."
  
  /usr/bin/ditto -rsrc "${app_mount}/VMware Fusion.app" "/Applications/VMware Fusion.app" > /dev/null 2>&1
  if [ ! $? -eq 0 ]; then
    logger_func ERROR "Installation failed."
  fi

  newly_installed_app_ver=`/usr/bin/defaults read "/Applications/VMware Fusion.app/Contents/Info.plist" CFBundleShortVersionString`
  if [ "${latest_app_ver}" = "${newly_installed_app_ver}" ]; then
    logger_func INFO "VMware Fusion has successfully been updated to version ${latest_app_ver}."
    cleanup_func 0
  else
    logger_func ERROR "VMware Fusion update failed."
  fi
}
### END OF FUNCTION DECLARATIONS

logger_func INFO "Starting VMwareFusionUpdate."

if [ '`/usr/bin/uname -p`'="i386" -o '`/usr/bin/uname -p`'="x86_64" ]; then
  os_version=$( /usr/bin/sw_vers -productVersion | /usr/bin/sed 's/[.]/_/g' )
  if [[ ! "${os_version}" =~ ^[0-9] ]]; then
    logger_func ERROR "Can't detect OS version."
  fi

  user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X ${os_version}) AppleWebKit/535.6.2 (KHTML, like Gecko) Version/5.2 Safari/535.6.2"
  
  if [ -f "/Applications/VMware Fusion.app/Contents/Info.plist" ]; then
    app_ver_func    
    logger_func INFO "Currently installed version is ${curr_installed_app_ver}, build ${curr_installed_app_build}."
    logger_func INFO "Latest version is ${latest_app_ver}, build ${latest_app_build}."
   
    if ! [[ "${curr_installed_app_ver}" == "${latest_app_ver}" ]]; then
      logger_func INFO "Latest available update is not installed, update needed."
      update_func
    else
      logger_func INFO "Latest available update is installed, no update needed."
    fi
    cleanup_func 0
    else
      logger_func ERROR "Can't find /Applications/VMware Fusion.app/Contents/Info.plist. Is VMware Fusion installed?"
  fi
else
  logger_func ERROR "This script is for Intel Macs only."
fi