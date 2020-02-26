#!/bin/bash
#####################################################################################################
#
# ABOUT THIS PROGRAM
#
# NAME
#   LibreOfficeUpdate.sh
#
# DESCRIPTION 
#   Updates LibreOffice on MacOS.
#   This script is provided as is, use at your own risk :)
#
# AUTHOR
#   https://github.com/pigeonpilot
#
# SYNOPSIS
#   sudo ./LibreOfficeUpdate.sh
#
####################################################################################################


declare latest_app_ver=""
declare curr_installed_app_ver=""
declare -r latest_app_url=""
declare -r log_file="/Library/Logs/LibreOfficeUpdate.log"
declare os_version=""
declare user_agent=""
# select stable or bleedingedge
declare train="bleedingedge"
declare extra_sort_opts=""
declare update_url="https://www.libreoffice.org/download/download/"
declare download_url="https://download.documentfoundation.org/libreoffice/stable"
declare dmg_file=""
declare app_mount=""
declare langpack_lang="sv"


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

umount_dmg_func () {
  if [ ! -z "${app_mount}" ]; then
    /usr/bin/hdiutil detach "${app_mount}" -quiet
    if [ ! $? -eq 0 ]; then
      logger_func CRIT "Failed to unmount installer image."
    else
      logger_func INFO "Unmounting installer image."
    fi
  fi
}

delete_dmg_func () {
  if [ -f "${dmg_file}" ] && [[ "${dmg_file}" =~ ^/tmp/.* ]]; then
    /bin/rm "${dmg_file}" > /dev/null 2>&1
    if [ ! $? -eq 0 ]; then
      logger_func CRIT "Failed to delete installer image file ${dmg_file}."
    else
      logger_func INFO "Successfully deleted installer image."
    fi
  fi
}

app_ver_func () {
  if [ ${train} = "bleedingedge" ]; then
    extra_sort_opts="-r"
  fi

  curr_installed_app_ver=`/usr/bin/defaults read "/Applications/LibreOffice.app/Contents/Info.plist" CFBundleGetInfoString | sed -n 's/LibreOffice \(.*\)\.[0-9]$/\1/p'`
  if [[ ! "${curr_installed_app_ver}" =~ ^[0-9]+ ]]; then
    logger_func ERROR "Error detecting installed version of LibreOffice."
  fi

  latest_app_url_data=`/usr/bin/curl --fail --connect-timeout 10 -m 300 -s -L -H 'Accept-Language: sv-SE' -A "${user_agent}" "${update_url}" | sed -n 's/.*\(http.*mac-x86_64\/\(.*\)\/sv\/LibreOffice.*MacOS_x86-64\.dmg\)\".*/\1 \2/p' | sort -n ${extra_sort_opts}| head -n 1 `
  if ! [ $? -eq 0 ]; then
    logger_func ERROR "Error when checking latest application URL."${latest_app_url}"."
  fi

  latest_app_ver=`/bin/echo ${latest_app_url_data} | cut -d " " -f 2`
  if [[ ! "${latest_app_ver}" =~ ^[0-9]+ ]]; then
    logger_func ERROR "Error detecting latest version of LibreOffice."
  fi  
}

update_func () {
  dmg_file="`/usr/bin/mktemp -q /tmp/XXXXXXXXXXXXXXXXXXXXXXXXX`"
  if [ $? -ne 0 ]; then
    logger_func ERROR "Can't create temp file, exiting..."
  fi

  /bin/echo "`/bin/date`: INFO: Downloading update..." >> "${log_file}"
  /usr/bin/curl -A "${user_agent}" --fail --connect-timeout 10 -m 300 -s -L -o "${dmg_file}" "${download_url}/${latest_app_ver}/mac/x86_64/LibreOffice_${latest_app_ver}_MacOS_x86-64.dmg"
  if [ $? -eq 0 ]; then
    logger_func INFO "Successfully downloaded ${download_url}/${latest_app_ver}/mac/x86_64/LibreOffice_${latest_app_ver}_MacOS_x86-64.dmg"
  else
    logger_func ERROR "Error when downloading ${download_url}/${latest_app_ver}/mac/x86_64/LibreOffice_${latest_app_ver}_MacOS_x86-64.dmg"
  fi

  app_mount="`/usr/bin/hdiutil attach "${dmg_file}" -nobrowse | /usr/bin/tail -n1 | /usr/bin/cut -f 3`"
  if [ ! $? -eq 0 ]; then
    logger_func ERROR "Failed to mount the installer disk image."
  else
    logger_func INFO "Mounted the installer disk image at "${app_mount}"."
  fi

  /bin/rm -rf "/Applications/LibreOffice.app"
  if [ ! $? -eq 0 ]; then
    logger_func ERROR "Failed to delete applicationfolder."
  fi

  /usr/bin/ditto -rsrc "${app_mount}/LibreOffice.app" "/Applications/LibreOffice.app" > /dev/null 2>&1
  if [ ! $? -eq 0 ]; then
    logger_func ERROR "Installation failed."
  fi

  newly_installed_ver=`/usr/bin/defaults read "/Applications/LibreOffice.app/Contents/Info.plist" CFBundleGetInfoString | sed -n 's/LibreOffice \(.*\)\.[0-9]$/\1/p'`
  if [ "${latest_app_ver}" = "${newly_installed_ver}" ]; then
    logger_func INFO "LibreOffice has successfully been updated to version ${latest_app_ver}."
  else
    logger_func ERROR "LibreOffice update failed."
  fi


  if [[ -n ${langpack_lang} ]]; then

    /bin/echo "`/bin/date`: INFO: Updating LibreOffice ${langpack_lang} languagepack." >> "${log_file}"

    umount_dmg_func
    delete_dmg_func

    dmg_file="`/usr/bin/mktemp -q /tmp/XXXXXXXXXXXXXXXXXXXXXXXXX`"
    if [ $? -ne 0 ]; then
      logger_func ERROR "Can't create temp file, exiting..."
    fi

    /bin/echo "`/bin/date`: INFO: Downloading LibreOffice ${langpack_lang} languagepack update..." >> "${log_file}"
    /usr/bin/curl -A "${user_agent}" --fail --connect-timeout 10 -m 300 -s -L -o "${dmg_file}" "${download_url}/${latest_app_ver}/mac/x86_64/LibreOffice_${latest_app_ver}_MacOS_x86-64_langpack_${langpack_lang}.dmg"
    if [ $? -eq 0 ]; then
      logger_func INFO "Successfully downloaded ${download_url}/${latest_app_ver}/mac/x86_64/LibreOffice_${latest_app_ver}_MacOS_x86-64_langpack_${langpack_lang}.dmg"
    else
      logger_func ERROR "Error when downloading ${download_url}/${latest_app_ver}/mac/x86_64/LibreOffice_${latest_app_ver}_MacOS_x86-64_langpack_${langpack_lang}.dmg"
    fi

    app_mount="`/usr/bin/hdiutil attach "${dmg_file}" -nobrowse | /usr/bin/tail -n1 | /usr/bin/cut -f 3`"
    if [ ! $? -eq 0 ]; then
      logger_func ERROR "Failed to mount the installer disk image."
    else
      logger_func INFO "Mounted the installer disk image at "${app_mount}"."
    fi

    tar -C /Applications/LibreOffice.app/ -xjf "${app_mount}/LibreOffice Language Pack.app/Contents/tarball.tar.bz2"
    if [ $? -ne 0 ]; then
      logger_func ERROR "Error installing languagepack."
    else
      logger_func INFO "Successfully installed LibreOffice ${langpack_lang} languagepack."
    fi
fi
}
### END OF FUNCTION DECLARATIONS

logger_func INFO "Starting LibreOfficeUpdate."

if [ '`/usr/bin/uname -p`'="i386" -o '`/usr/bin/uname -p`'="x86_64" ]; then
  os_version=$( /usr/bin/sw_vers -productVersion | /usr/bin/sed 's/[.]/_/g' )
  if [[ ! "${os_version}" =~ ^[0-9] ]]; then
    logger_func ERROR "Can't detect OS version."
  fi
  user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X ${os_version}) AppleWebKit/535.6.2 (KHTML, like Gecko) Version/5.2 Safari/535.6.2"
   if [ -f "/Applications/LibreOffice.app/Contents/Info.plist" ]; then
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
     logger_func ERROR "Can't find /Applications/LibreOffice.app/Contents/Info.plist. Is LibreOffice installed?"
  fi

else
  logger_func ERROR "This script is for Intel Macs only."
fi