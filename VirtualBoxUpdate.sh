#!/bin/bash
#####################################################################################################
#
# ABOUT THIS PROGRAM
#
# NAME
#   VirtualBoxUpdate.sh
#
# DESCRIPTION 
#   Updates Oracle VirtualBox on Mac OS.
#   This script is provided as is, use at your own risk :)
#
# AUTHOR
#   https://github.com/pigeonpilot
#
# SYNOPSIS
#   sudo ./VirtualBoxUpdate.sh
#
####################################################################################################

declare app_mount=""
declare curr_installed_app_build=""
declare curr_installed_app_ver=""
declare curr_installed_app_major=""
declare dmg_file=""
declare ext_tmp_dir=""
declare latest_app_build=""
declare latest_app_ver=""
declare -r log_file="/Library/Logs/VirtualBoxUpdate.log"
declare os_version=""
declare -r update_url="https://www.virtualbox.org/wiki/Downloads"
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
  delete_ext_tmp_func
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
      logger_func CRIT "Failed to delete installer image file ${dmg_file}."
    else
      logger_func INFO "Successfully deleted installer image."
    fi
  fi
}

delete_ext_tmp_func () {
  if [ -d "${ext_tmp_dir}" ] && [[ "${ext_tmp_dir}" =~ ^/tmp/.* ]]; then
    /bin/rm -rf "${ext_tmp_dir}" > /dev/null 2>&1
    if [ ! $? -eq 0 ]; then
      logger_func CRIT "Failed to delete temporary extensionpack directory ${ext_tmp_file}."
    else
      logger_func INFO "Successfully deleted temporary extensionpack directory."
    fi
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

app_ver_func () {
  curr_installed_app_ver=`/usr/bin/defaults read "/Applications/VirtualBox.app/Contents/Info.plist" CFBundleVersion`
  if [[ ! "${curr_installed_app_ver}" =~ ^[0-9]+ ]]; then
    logger_func ERROR "Error detecting installed version of Oracle VirtualBox."
  fi

  latest_app_url=`/usr/bin/curl --fail --connect-timeout 10 -m 300 -s -L -A "${user_agent}" "${update_url}" | /usr/bin/sed -n 's/.*href="\(.*-OSX.dmg\)\"><.*/\1/p'`
  if ! [ $? -eq 0 ]; then
    logger_func ERROR "Error when checking latest application URL."${latest_app_url}"."
  fi

  latest_app_ver=`/bin/echo ${latest_app_url} | sed -n 's/.*download.virtualbox.org\/virtualbox\/\(.*\)\/VirtualBox.*/\1/p'`
  if [[ ! "${latest_app_ver}" =~ ^[0-9]+ ]]; then
    logger_func ERROR "Error detecting latest version of Oracle VirtualBox."
  fi  
}

extpack_ver_func () {

  curr_installed_extpack_ver=`/Applications/VirtualBox.app/Contents/MacOS/VBoxManage list extpacks | grep "Version:" | rev | cut -d " " -f 1 | rev`
  latest_extpack_url=`/usr/bin/curl --fail --connect-timeout 10 -m 300 -s -L -A "${user_agent}" "${update_url}" | /usr/bin/sed -n 's/.*href="\(.*.vbox-extpack\)\"><.*/\1/p'`
  if ! [ $? -eq 0 ]; then
    logger_func ERROR "Error when checking latest extensionpack URL."${latest_app_url}"."
  fi
  latest_extpack_ver=`/bin/echo ${latest_extpack_url} | sed -n 's/.*Oracle_VM_VirtualBox_Extension_Pack-\(.*\).vbox-extpack/\1/p'`
  latest_extpack_filename=`/bin/echo "${latest_extpack_url}" | /usr/bin/sed -n 's/.*\/\(.*\)/\1/p' `
}

update_app_func () {
  dmg_file="`/usr/bin/mktemp -q /tmp/XXXXXXXXXXXXXXXXXXXXXXXXX`"
  if [ $? -ne 0 ]; then
    logger_func ERROR "Can't create temp file, exiting..."
  fi
  logger_func INFO "Downloading update..."
  /usr/bin/curl -A "${user_agent}" --fail --connect-timeout 10 -m 300 -s -o "${dmg_file}" "${latest_app_url}"
  if [ $? -eq 0 ]; then
    logger_func INFO "Successfully downloaded "${latest_app_url}"."
  else
    logger_func ERROR "Error when downloading "${latest_app_url}"."
  fi
  app_mount="`/usr/bin/hdiutil attach "${dmg_file}" -nobrowse | /usr/bin/tail -n1 | /usr/bin/cut -f 3`"
    if [ ! $? -eq 0 ]; then
      logger_func ERROR "ERROR: Failed to mount the installer disk image."
    else
      logger_func INFO "Mounted the installer disk image at ${app_mount}."
      app_pkg_path=`/usr/bin/find "${app_mount}" -type f -name "VirtualBox.pkg"`
      if [[ "${app_pkg_path}" != "" ]]; then


        if /usr/sbin/pkgutil --check-signature "${app_pkg_path}" | /usr/bin/grep -s "Status: signed by a certificate trusted by Mac OS X" > /dev/null 2>&1; then
          logger_func INFO "Installer certificate is valid, installing..."
          installer_err=`/usr/sbin/installer -pkg "${app_pkg_path}" -target "/" -verboseR | "/usr/bin/grep" "was successful."`
          if [[ "${installer_err}" =~ "was successful." ]]; then
            logger_func INFO "Successfully upgraded Oracle VirtualBox to version "${latest_app_ver}"."
          else
            logger_func ERROR "Installation of Oracle VirtualBox version "${latest_app_ver}" failed."
          fi
        else
          logger_func ERROR "Installer failed certificate check!"
        fi
      else
        logger_func ERROR "Cannot find installer in ${app_mount}."
      fi
    fi
}

update_extpack_func () {
  ext_tmp_dir="`/usr/bin/mktemp -qd /tmp/XXXXXXXXXXXXXXXXXXXXXXXXX`"
  if [ $? -ne 0 ]; then
    logger_func ERROR "Can't create temp directory for extensionpack, exiting..."
  fi
  logger_func INFO "Downloading extensionpack update..."
  cd ${ext_tmp_dir}
  /usr/bin/curl -A "${user_agent}" --fail --connect-timeout 10 -m 300 -s -o "${ext_tmp_dir}/${latest_extpack_filename}" "${latest_extpack_url}"
  if [ $? -eq 0 ]; then
    logger_func INFO "Successfully downloaded "${latest_extpack_url}"."
  else
    logger_func ERROR "Error when downloading "${latest_extpack_url}"."
  fi
  cd -
  installer_err=""
  installer_err=`yes | /Applications/VirtualBox.app/Contents/MacOS/VBoxManage extpack install --replace "${ext_tmp_dir}/${latest_extpack_filename}" | /usr/bin/sed -n 's/.*\(Successfully installed\).*/\1/p'`  
  if [[ ${installer_err} = "Successfully installed" ]]; then
    logger_func INFO "Successfully installed Oracle VirtualBox extensionpack."
    if [[ `/Applications/VirtualBox.app/Contents/MacOS/VBoxManage extpack cleanup` == "Successfully performed extension pack cleanup" ]]; then
      logger_func INFO "Successfully cleaned up extensionpacks."
    else
      logger_func CRIT "Error when cleaning up extensionpacks.."
    fi
  else
    logger_func ERROR "Error when installing Oracle VirtualBox extensionpack."
  fi
}
### END OF FUNCTION DECLARATIONS

logger_func INFO "Starting VirtualBoxUpdate." 

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
    extpack_ver_func
    if ! [[ "${curr_installed_extpack_ver}" == "${latest_extpack_ver}" ]]; then
      logger_func INFO "Latest available extensionpack is not installed, update needed."
      update_extpack_func
    else
      logger_func INFO "Latest available extensionpack is installed, no update needed."
    fi
    cleanup_func 0
  else
    logger_func ERROR "Can't find /Applications/VirtualBox.app/Contents/Info.plist. Is Oracle VirtualBox installed?"
  fi
else
  logger_func ERROR "This script is for Intel Macs only."
fi