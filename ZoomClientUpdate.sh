#!/bin/bash
#####################################################################################################
#
# ABOUT THIS PROGRAM
#
# NAME
#   ZoomClientUpdate.sh
#
# DESCRIPTION 
#   Updates Zoom.us on Mac OS.
#   This script is provided as is, use at your own risk :)
#
# AUTHOR
#   https://github.com/pigeonpilot
#
# SYNOPSIS
#   sudo ./ZoomClientUpdate.sh
#
####################################################################################################

# TODO fix sigcheck

declare latest_app_ver=""
declare curr_installed_app_ver=""
declare -r latest_app_url="https://zoom.us/client/latest/Zoom.pkg"
declare -r log_file="/Library/Logs/ZoomClientUpdate.log"
declare os_version=""
declare signature_check=""
declare tmp_pkg_dir=""
declare -r update_url="https://zoom.us/download#client_4meeting"
declare user_agent=""


### START OF FUNCTION DECLARATIONS
logger_func () {
  /bin/echo "`/bin/date '+%Y-%m-%d %H:%M:%S'` `/usr/bin/basename "$0"` $1: $2" | /usr/bin/tee -a "${log_file}"
  if [ $1 = "ERROR" ]; then
    cleanup_func 1
  fi
}

cleanup_func () {
  logger_func INFO "End of script."
  delete_pkg_func
  if [ -z "${1}" ]; then
    exit 1
  else
    exit "${1}"
  fi
}

delete_pkg_func () {
  if [ -d "${tmp_pkg_dir}" ] && [[ "${tmp_pkg_dir}" =~ ^/tmp/.* ]]; then
    /bin/rm -rf "${tmp_pkg_dir}" > /dev/null 2>&1
    if [ ! $? -eq 0 ]; then
      logger_func WARN "Failed to delete installer files ${tmp_pkg_dir}."
    else
      logger_func INFO "Successfully deleted installer files."
    fi
  fi
}

app_ver_func () {
  curr_installed_app_ver=`/usr/bin/defaults read "/Applications/zoom.us.app/Contents/Info.plist" CFBundleVersion`
  if [[ ! "${curr_installed_app_ver}" =~ ^[0-9]+ ]]; then
    logger_func ERROR "Error detecting installed version of Zoom.us Client."
  fi

  latest_app_ver=`/usr/bin/curl --fail --connect-timeout 10 -m 300 -s -L -A "${user_agent}" "${update_url}" |  /usr/bin/grep -A3 "https://zoom.us/client/latest/Zoom.pkg" | /usr/bin/sed -n 's/^Version \(.*\)<\/div>/\1/p'`
  if ! [ $? -eq 0 ]; then
    logger_func ERROR "Error when checking latest application URL."${latest_app_url}"."
  fi
}

update_app_func () {
  tmp_pkg_dir="`/usr/bin/mktemp -qd /tmp/XXXXXXXXXXXXXXXXXXXXXXXXX`"
  if [ $? -ne 0 ]; then
    logger_func ERROR "Can't create tempfile, exiting..."
  fi
  logger_func INFO "Downloading Zoom.us Client update..."
  /usr/bin/curl -A "${user_agent}" --fail --connect-timeout 10 -m 300 -L -s -o "${tmp_pkg_dir}/Zoom.pkg" "${latest_app_url}"

  if [ $? -eq 0 ]; then
    logger_func INFO "Successfully downloaded "${tmp_pkg_dir}/Zoom.pkg"."
  else
    logger_func ERROR "Error when downloading "${tmp_pkg_dir}/Zoom.pkg"."
  fi

  signature_check=`/usr/sbin/pkgutil --check-signature "${tmp_pkg_dir}/Zoom.pkg" | /usr/bin/awk /'Developer ID Installer/{ print $5 }'`
  if [[ "${signature_check}" = "Zoom" ]]; then
    logger_func INFO "Installer certificate is valid, installing..."
    /usr/sbin/installer -pkg "${tmp_pkg_dir}/Zoom.pkg" -target "/" -verboseR > /dev/null 2>&1
    if [ $? -eq 0 ]; then
      logger_func INFO "Zoom.us Client version ${latest_app_ver} was successfully installed."
    else
      logger_func ERROR "Installation of Zoom.us Client version ${latest_app_ver} failed."
    fi
  else
    logger_func ERROR "Installer failed certificate check!"
  fi
}
### END OF FUNCTION DECLARATIONS

logger_func INFO "Starting ZoomClientUpdate." 

if [ '`/usr/bin/uname -p`'="i386" -o '`/usr/bin/uname -p`'="x86_64" ]; then
  os_version=$( /usr/bin/sw_vers -productVersion | /usr/bin/sed 's/[.]/_/g' )
  if [[ ! "${os_version}" =~ ^[0-9] ]]; then
    logger_func ERROR "Can't detect OS version."
  fi
  user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X ${os_version}) AppleWebKit/535.6.2 (KHTML, like Gecko) Version/5.2 Safari/535.6.2"
  if [ -f "/Applications/VirtualBox.app/Contents/Info.plist" ]; then
    app_ver_func
    logger_func INFO "Currently installed version is ${curr_installed_app_ver}."
    logger_func INFO "Latest version is ${latest_app_ver}."
    if ! [[ "${curr_installed_app_ver}" == "${latest_app_ver}" ]]; then
      logger_func INFO "Latest available update is not installed, update needed."
      update_app_func
    else
      logger_func INFO "Latest available update is installed, no update needed."
    fi
    cleanup_func 0
  else
    logger_func ERROR "Can't find /Applications/zoom.us.app/Contents/Info.plist. Is Zoom.us Client installed?"
  fi
else
  logger_func ERROR "This script is for Intel Macs only."
fi

