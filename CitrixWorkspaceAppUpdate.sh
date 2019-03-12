#!/bin/bash
#####################################################################################################
#
# ABOUT THIS PROGRAM
#
# NAME
#   CitrixWorkspaceappUpdate.sh
#
# DESCRIPTION 
#   Updates Citrix Workspace app on macOS.
#
# AUTHOR
#   https://github.com/pigeonpilot
#
# SYNOPSIS
#   sudo ./CitrixWorkspaceappUpdate.sh
#
####################################################################################################

declare app_mount=""
declare -r app_url="https://www.citrix.se/downloads/workspace-app/mac/workspace-app-for-mac-latest.html"
declare curr_installed_app_ver=""
declare dmg_file=""
declare latest_app_ver=""
declare -r log_file="/Library/Logs/CitrixWorkspaceappUpdate.log"
declare os_version=""
declare user_agent=""

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
  curr_installed_app_ver=`/usr/bin/defaults read "/Applications/Citrix Workspace.app/Contents/Info.plist" CitrixVersionString`
  if [[ "${curr_installed_app_ver}" =~ ^[0-9]+ ]]; then
    curr_installed_app_major=`/bin/echo $curr_installed_app_ver | /usr/bin/cut -d "." -f 1`
  else
    logger_func ERROR "Error detecting installed version."
  fi

  latest_app_ver=`/usr/bin/curl --fail --connect-timeout 10 -m 300 -s -L -A "${user_agent}" "${app_url}" | /usr/bin/sed -n 's/<p>Version:&nbsp;\(.*\) (.*/\1/p'`
  if [[ ! "${latest_app_ver}" =~ ^[0-9]+ ]]; then
    logger_func ERROR "Error detecting latest version."
  fi
}

update_func () {

  dmg_file="`/usr/bin/mktemp -q /tmp/XXXXXXXXXXXXXXXXXXXXXXXXX`"
  if [ $? -ne 0 ]; then
    logger_func ERROR "Can't create temp file, exiting..."
    cleanup_func 1
  fi

  logger_func INFO "Downloading update..."

  declare -r download_url=`/usr/bin/curl -A "${user_agent}" --fail --connect-timeout 10 -m 300 -s "${app_url}" | /usr/bin/sed -n 's/.*rel="\/\/\(downloads.citrix.com.*\)" id=".*/\1/p'`
  /usr/bin/curl -A "${user_agent}" --fail --connect-timeout 10 -m 300 -s -o "${dmg_file}" "${download_url}"
  if [ $? -eq 0 ]; then
    logger_func INFO "Successfully downloaded update"
  else
    logger_func ERROR "Error when downloading ${download_url}"
  fi


  app_mount="`/usr/bin/hdiutil attach "${dmg_file}" -nobrowse | /usr/bin/tail -n1 | /usr/bin/cut -f 3`"
  if [ ! $? -eq 0 ]; then
    logger_func ERROR "Failed to mount the installer disk image."
  else
    logger_func INFO "Mounted the installer disk image at "${app_mount}"."
  fi

  logger_func INFO "Installing updated version of Citrix Workspace."

  app_pkg_path=`/usr/bin/find "${app_mount}" -type f -name "Install Citrix Workspace.pkg"`

  if [[ "${app_pkg_path}" != "" ]]; then
    signature_check=`/usr/sbin/pkgutil --check-signature "${app_pkg_path}" | /usr/bin/grep -A100 "Status: signed by a certificate trusted by Mac OS X" | /usr/bin/sed -n 's/.*Developer ID Installer: \(Citrix Systems\).*/\1/p'`
    if [[ "${signature_check}" = "Citrix Systems" ]]; then
      logger_func INFO "Package certificate seems valid, installing..."
      installer_err=`/usr/sbin/installer -pkg "${app_pkg_path}" -target "/" -verboseR | "/usr/bin/grep" "was successful."`
      if [[ "${installer_err}" =~ "was successful." ]]; then
        logger_func INFO "Citrix Workspace version ${latest_app_ver} was successfully installed."
      else
        logger_func ERROR "Installation of Citrix Workspace version ${latest_app_ver} failed."
      fi
    else
      logger_func ERROR "Installer failed certificate check!"
    fi
  else
    logger_func ERROR "Cannot find installer in ${app_mount}."
  fi
}
### END OF FUNCTION DECLARATIONS


logger_func INFO "Starting Citrix Workspace update."

if [ '`/usr/bin/uname -p`'="i386" -o '`/usr/bin/uname -p`'="x86_64" ]; then
  os_version=$( /usr/bin/sw_vers -productVersion | /usr/bin/sed 's/[.]/_/g' )
  if [[ ! "${os_version}" =~ ^[0-9] ]]; then
    logger_func ERROR "Can't detect OS version."
  fi

  user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X ${os_version}) AppleWebKit/535.6.2 (KHTML, like Gecko) Version/5.2 Safari/535.6.2"


  if [ -f "/Applications/Citrix Workspace.app/Contents/Info.plist" ]; then
  
    app_ver_func
    
    logger_func INFO "Currently installed version is ${curr_installed_app_ver}."
    logger_func INFO "Latest version is ${latest_app_ver}."
   
    if ! [[ "${curr_installed_app_ver}" == "${latest_app_ver}" ]]; then
      logger_func INFO "Latest available update is not installed, update needed."
      update_func
    else
      logger_func INFO "Latest available update is installed, no update needed."
    fi

    cleanup_func 0

  else
    logger_func ERROR "Can't find /Applications/Citrix Workspace.app/Contents/Info.plist. Is Citrix Workspace app installed?"
  fi

else
  logger_func ERROR "This script is for Intel Macs only."
fi