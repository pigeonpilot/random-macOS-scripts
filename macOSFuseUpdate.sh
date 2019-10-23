#!/bin/bash
#####################################################################################################
#
# ABOUT THIS PROGRAM
#
# NAME
#   macOSFuseUpdate.sh
#
# DESCRIPTION 
#   Updates Fuse on Mac OS.
#   This script is provided as is, use at your own risk :)
#
# AUTHOR
#   https://github.com/pigeonpilot
#
# SYNOPSIS
#   sudo ./macOSFuseUpdate.sh
#
####################################################################################################


declare -r log_file="/Library/Logs/macOSFuseUpdate.log"
declare app_mount=""
declare curr_installed_app_ver=""
declare dmg_file=""
declare -r latest_url="https://github.com/osxfuse/osxfuse/releases/latest"
declare download_url=""
declare latest_app_ver=""
declare os_version=""
declare -r update_url=""
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
  curr_installed_app_ver=`/usr/bin/defaults read "/Library/Filesystems/osxfuse.fs/Contents/Info.plist" CFBundleShortVersionString`
  if ! [[ "${curr_installed_app_ver}" =~ ^[0-9]+ ]]; then
    logger_func ERROR "Error detecting installed version of macOS FUSE."
  fi

  download_url=`/usr/bin/curl --fail --connect-timeout 10 -m 300 -s -L -A "${user_agent}" "${latest_url}" | /usr/bin/sed -n 's/.*<a href=\"\/\(.*.dmg\)\"\s*.*/\1/p'`

  latest_app_ver=`/bin/echo ${download_url} | /usr/bin/sed -n 's/^osxfuse\/osxfuse\/releases\/download\/osxfuse-[0-9.]*\/osxfuse-\([0-9.]*\)\.dmg$/\1/p'`
  if ! [[ "${latest_app_ver}" =~ ^[0-9]+ ]]; then
    logger_func ERROR "Error detecting latest version of VMware Fusion."
  fi
}

update_func () {
  dmg_file="`/usr/bin/mktemp -q /tmp/XXXXXXXXXXXXXXXXXXXXXXXXX`"
  if [ $? -ne 0 ]; then
    logger_func ERROR "Can't create temp file, exiting..."
  fi

  logger_func INFO "Downloading update..."

  /usr/bin/curl -L -A "${user_agent}" --fail --connect-timeout 10 -m 900 -s -o "${dmg_file}" "https://github.com/${download_url}"
  if [ $? -eq 0 ]; then
    logger_func INFO "Successfully downloaded http://github.com/${download_url}."
  else
    logger_func ERROR "Error when downloading https://github.com/${download_url}."
  fi

  app_mount="`/usr/bin/hdiutil attach "${dmg_file}" -nobrowse | /usr/bin/sed -n 's/^\/dev\/[^/S]*\(.*\)$/\1/p'`"
  if [ ! $? -eq 0 ]; then
    logger_func ERROR "Failed to mount the installer disk image."
  else
    logger_func INFO "Mounted the installer disk image at ${app_mount}."
 
    app_pkg_path=`/usr/bin/find "${app_mount}" -type f -iname "*.pkg"`
    if [[ "${app_pkg_path}" != "" ]]; then

      if /usr/sbin/pkgutil --check-signature "${app_pkg_path}" | /usr/bin/egrep -s "Status: signed by a.* certificate trusted|issued by Mac OS X|Apple" > /dev/null 2>&1; then
        logger_func INFO "Installer certificate is valid, installing..."
        installer_err=`/usr/sbin/installer -pkg "${app_pkg_path}" -target "/" -verboseR | "/usr/bin/grep" "was successful."`
        if [[ "${installer_err}" =~ "was successful." ]]; then
          logger_func INFO "Successfully upgraded macOS FUSE to version "${latest_app_ver}"."
        else
          logger_func ERROR "Installation of macOS FUSE version "${latest_app_ver}" failed."
        fi
      else
        logger_func INFO "Installer certificate is valid, installing..."
      fi
    else
      logger_func ERROR "Cannot find installer in ${app_mount}."
    fi
  fi
}
### END OF FUNCTION DECLARATIONS

logger_func INFO "Starting macOSFuseUpdate." 

if [ '`/usr/bin/uname -p`'="i386" -o '`/usr/bin/uname -p`'="x86_64" ]; then
  os_version=$( /usr/bin/sw_vers -productVersion | /usr/bin/sed 's/[.]/_/g' )
  if [[ ! "${os_version}" =~ ^[0-9] ]]; then
    logger_func ERROR "Can't detect OS version."
  fi
  user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X ${os_version}) AppleWebKit/535.6.2 (KHTML, like Gecko) Version/5.2 Safari/535.6.2"
  
  if [ -f "/Library/Filesystems/osxfuse.fs/Contents/Info.plist" ]; then
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
  fi
else
  logger_func ERROR "This script is for Intel Macs only."
fi