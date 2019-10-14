#!/bin/bash
#####################################################################################################
#
# ABOUT THIS PROGRAM
#
# NAME
#   AcrobatDCUpdate.sh
#
# DESCRIPTION 
#   Updates Adobe Acrobat/Reader DC on Mac OS.
#   Inspired by https://www.jamf.com/jamf-nation/discussions/26075/adobe-acrobat-pro-dc-update-script
#   This script is provided as is, use at your own risk :)
#
# AUTHOR
#   https://github.com/pigeonpilot
#
# SYNOPSIS
#   sudo ./AcrobatDCUpdate.sh
#
####################################################################################################

declare app_mount=""
declare app_name=""
declare app_path=""
declare current_installed_ver=""
declare dmg_file=""
declare exit_status="1"
declare latest_ver=""
declare -r log_file="/Library/Logs/AcrobatDCUpdate.log"
declare os_version=""
declare user_agent=""

trap cleanup_func 1 2 3 6 15

set -u

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
  latest_ver=`/usr/bin/curl --fail --connect-timeout 10 -m 300 -s -L -A "${user_agent}" "${latest_ver_url}" | /usr/bin/rev | /usr/bin/cut -d " " -f 1 | /usr/bin/rev | /usr/bin/grep [0-9] | /usr/bin/sort | /usr/bin/tail -n 1`
  if [[ "${latest_ver}" =~ ^[0-9]+ ]]; then
    current_installed_ver=`/usr/bin/defaults read "${app_path}/Contents/Info" CFBundleShortVersionString | /usr/bin/sed 's/[^0-9]//g'`
    if [[ ! "${current_installed_ver}" =~ ^[0-9]+ ]]; then
      logger_func ERROR "Cannot detect current version of ${app_name}."
    fi
    
    current_track_name=`/usr/bin/defaults read "${app_path}/Contents/Info" TrackName`
    if [[ ! "${current_track_name}" = "DC" ]]; then
      logger_func ERROR "Wrong trackname detected for ${app_name}. This script only supports DC versions."
    fi
  else
    logger_func ERROR "Cannot detect latest update for ${app_name}."
  fi
}

umount_dmg_func () {
  if [ ! -z "${app_mount}" ]; then
    /usr/bin/hdiutil detach "${app_mount}" -quiet
    if [ ! $? -eq 0 ]; then
      logger_func WARN "Failed to unmount installer image."
    else
      logger_func INFO "INFO: Unmounting installer image."
    fi
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

update_func () {
  if [ ! "${latest_ver}" = "${current_installed_ver}" ]; then
    logger_func INFO "Installed version of ${app_name} is: ${current_installed_ver} latest version is: ${latest_ver}, update needed."
    
    if [ `/bin/ps -e | /usr/bin/pgrep -f "/Applications/${app_name}" | /usr/bin/wc -c` -gt 0 ]; then
      logger_func ERROR "Unable to install update when "${app_name}" is running."
    fi

    dmg_file="`/usr/bin/mktemp -q /tmp/XXXXXXXXXXXXXXXXXXXXXXXXX`"
    if [ $? -ne 0 ]; then
      logger_func ERROR "Can't create temp file, exiting..."
    fi
    
    logger_func INFO "Downloading update..."
    /usr/bin/curl --fail --connect-timeout 10 -m 900 -s -o "${dmg_file}" "${download_url}"
    if [ $? -eq 0 ]; then
      logger_func INFO "Successfully downloaded ${download_url}."
    else
      logger_func ERROR "Error when downloading ${download_url}."
    fi

    app_mount="`/usr/bin/hdiutil attach "${dmg_file}" -nobrowse | /usr/bin/tail -n1 | /usr/bin/cut -f 3`"
    if [ ! $? -eq 0 ]; then
      logger_func ERROR "Failed to mount the installer disk image."
    else
      logger_func INFO "Mounted the installer disk image at ${app_mount}."

      app_pkg_path=`/usr/bin/find "${app_mount}" -type f -name *.pkg`

      # TODO fix sigcheck
      if [[ "${app_pkg_path}" != "" ]]; then
        if /usr/sbin/pkgutil --check-signature "${app_pkg_path}" | /usr/bin/egrep -s "Status: signed by a.* certificate trusted|issued by Mac OS X|Apple" > /dev/null 2>&1; then
          logger_func INFO "Installer certificate is valid, installing..."
          installer_err=`/usr/sbin/installer -pkg "${app_pkg_path}" -target "/" -verboseR | "/usr/bin/grep" "was successful."`
          if [[ "${installer_err}" =~ "was successful." ]]; then
            logger_func INFO "Update ${latest_ver} for ${app_name} was successfully installed."
          else
            logger_func ERROR "Update ${latest_ver} for ${app_name} failed."
          fi
        else
          logger_func ERROR "Installer failed certificate check!"
        fi
      else
        logger_func ERROR "Cannot find installer in ${app_mount}."
      fi
    fi
  else
    logger_func INFO "${app_name} is already latest version ${latest_ver}."
  fi
}
### END OF FUNCTION DECLARATIONS

logger_func INFO "Starting AcrobatDCUpdate."

if [ '`/usr/bin/uname -p`'="i386" -o '`/usr/bin/uname -p`'="x86_64" ]; then
  os_version=$( /usr/bin/sw_vers -productVersion | /usr/bin/sed 's/[.]/_/g' )
  if [[ ! "${os_version}" =~ ^[0-9] ]]; then
    logger_func ERROR "Can't detect OS version"
  fi
  user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X ${os_version}) AppleWebKit/535.6.2 (KHTML, like Gecko) Version/5.2 Safari/535.6.2"
  app_path="/Applications/Adobe Acrobat DC/Adobe Acrobat.app"
  app_name="Adobe Acrobat DC"
  latest_ver_url="ftp://ftp.adobe.com/pub/adobe/acrobat/mac/AcrobatDC/"
  if [ -e "${app_path}" ]; then
    app_ver_func
    download_url="http://ardownload.adobe.com/pub/adobe/acrobat/mac/AcrobatDC/${latest_ver}/AcrobatDCUpd${latest_ver}.dmg"
    update_func
  else
    logger_func INFO "Cannot detect ${app_name} being installed"
  fi
  app_path="/Applications/Adobe Acrobat Reader DC.app"
  app_name="Adobe Acrobat Reader DC"
  latest_ver_url="ftp://ftp.adobe.com/pub/adobe/reader/mac/AcrobatDC/"
  if [ -e "${app_path}" ]; then
    app_ver_func
    download_url="http://ardownload.adobe.com/pub/adobe/reader/mac/AcrobatDC/${latest_ver}/AcroRdrDCUpd${latest_ver}_MUI.dmg"
    update_func
  else
    logger_func INFO "Cannot detect ${app_name} being installed"
  fi
  cleanup_func 0
fi