#!/bin/bash
#####################################################################################################
#
# ABOUT THIS PROGRAM
#
# NAME
#   FlashUpdate.sh
#
# DESCRIPTION 
#   Updates Adobe Flash Plugin(s) to latest version on Mac OS.
#   Inspired by https://www.jamf.com/jamf-nation/discussions/23579/ppapi-version-check-update-script
#   This script is provided as is, use at your own risk :)
#
# AUTHOR
#   https://github.com/pigeonpilot
#
# SYNOPSIS
#   sudo ./FlashUpdate.sh
#
####################################################################################################

set -u

declare app_mount=""
declare app_pkg=""
# Set AutoUpdateDisable=0 to enable automatic updates.
declare -r AutoUpdateDisable=0
declare config_checked=0
# Set DisableAnalytics=1 to disable analytics.
declare -r DisableAnalytics=1
declare dmg_file=""
declare download_url=""
declare exit_status="1"
declare installed_app_path=""
declare installed_app_ver=""
declare installer_err=""
declare latest_app_ver=""
declare -r log_file="/Library/Logs/FlashUpdateScript.log"
declare plugin_name=""
declare -r settings_directory="/Library/Application Support/Macromedia"
declare -r settings_file="mms.cfg"
declare signature_check=""
declare -r SilentAutoUpdateEnable=$((1-AutoUpdateDisable))

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

update_plugin_func () {
  if [ -e "${installed_app_path}/Contents/Info.plist" ]; then
    installed_app_ver=`/usr/bin/defaults read "${installed_app_path}/Contents/Info.plist" CFBundleShortVersionString`
    latest_app_ver=`/usr/bin/curl --fail --connect-timeout 10 -m 300 -s -A "${user_agent}" "${latest_app_path}" | /usr/bin/awk -F \" /"update version="/'{print $2}' | /usr/bin/sed s/,/./g`

    if [[ "${installed_app_ver}" =~ ^[0-9]+ ]] && [[ "${latest_app_ver}" =~ ^[0-9]+ ]]; then
      if [ "${installed_app_ver}" != "${latest_app_ver}" ]; then
        dmg_file="`/usr/bin/mktemp -q /tmp/XXXXXXXXXXXXXXXXXXXXXXXXX`"
        if [ $? -ne 0 ]; then
          logger_func ERROR "Can't create temp file, exiting..."
        fi

        case "${plugin_name}" in
          NPAPI)
            download_url="https://fpdownload.adobe.com/get/flashplayer/pdc/${latest_app_ver}/install_flash_player_osx.dmg"
            ;;
          PPAPI)
            download_url="https://fpdownload.adobe.com/get/flashplayer/pdc/${latest_app_ver}/install_flash_player_osx_ppapi.dmg"
            ;;
          *)
            logger_func ERROR "unknown plugin!"
        esac

        logger_func INFO "Installed version of Adobe Flash ${plugin_name} plugin is ${installed_app_ver}, latest available version is ${latest_app_ver}. Update needed."
        logger_func INFO "Downloading Adobe Flash ${plugin_name} ${latest_app_ver}..."
        /usr/bin/curl -s -o "${dmg_file}" "${download_url}"
        if [ $? -eq 0 ]; then
          logger_func INFO "Successfully downloaded $download_url."
        else
          logger_func ERROR "Error when downloading $download_url."
        fi

        app_mount="`/usr/bin/hdiutil attach "${dmg_file}" -nobrowse | /usr/bin/tail -n1 | /usr/bin/cut -f 3`"
        if [ ! $? -eq 0 ]; then
          logger_func ERROR "Failed to mount the installer disk image."
        else
          logger_func INFO "Mounted the installer disk image at ${app_mount}."

          app_pkg_path=`/usr/bin/find "${app_mount}" -type f -name "Adobe Flash Player.pkg"`

          if [[ "${app_pkg_path}" != "" ]]; then
            signature_check=`/usr/sbin/pkgutil --check-signature "${app_pkg_path}" | /usr/bin/awk /'Developer ID Installer/{ print $5 }'`
            if [[ "${signature_check}" = "Adobe" ]]; then
              logger_func INFO "Installer certificate is valid, installing..."
              installer_err=`/usr/sbin/installer -pkg "${app_pkg_path}" -target "/" -verboseR | "/usr/bin/grep" "was successful."`
              if [[ "${installer_err}" =~ "was successful." ]]; then
                logger_func INFO "Adobe Flash ${plugin_name} version ${latest_app_ver} was successfully installed."
              else
                logger_func ERROR "Installation of Adobe Flash ${plugin_name} version ${latest_app_ver} failed."
              fi
            else
              logger_func ERROR "Installer failed certificate check!"
            fi
          else
            logger_func ERROR "Cannot find installer in ${app_mount}."
          fi
        fi
      else
        logger_func INFO "Installed version of Adobe Flash ${plugin_name} is ${installed_app_ver}, latest available is ${latest_app_ver}. Update not needed."
      fi
    else
      logger_func ERROR "Error in versioncheck."
    fi

    if [ ! -d "${settings_directory}" ]; then
      if `/bin/mkdir -m 755 "${settings_directory}"`; then
        logger_func INFO "Created settings directory ${settings_directory}."
      else
        logger_func WARN "Failed to create settings directory ${settings_directory}."
      fi
    fi

    if [ ! -f "${settings_directory}/${settings_file}" ]; then
      if `/usr/bin/install -m 644 /dev/null "${settings_directory}/${settings_file}"`; then
        logger_func INFO "Created settings file ${settings_directory}/${settings_file}."
      else
        logger_func WARN "Failed to create settings file ${settings_directory}/${settings_file}."
      fi
    fi

    if [ ${config_checked} == 0 ]; then
      check_update_settings AutoUpdateDisable
      check_update_settings SilentAutoUpdateEnable
      check_update_settings DisableAnalytics
      config_checked=1
    fi
  else
    logger_func INFO "${plugin_name} is not installed."
  fi
  unset installed_app_ver
  unset latest_app_ver
}

check_update_settings () {
  if [ ${!1} == 1 -o ${!1} == 0 ]; then
    if `/usr/bin/grep -q -r "$1" "${settings_directory}/${settings_file}"`; then
      if [[ `/usr/bin/grep "$1" "${settings_directory}/${settings_file}" | /usr/bin/cut -d "=" -f 2` -ne "${!1}" ]]; then
        if `/usr/bin/sed -i -e "s/$1=[01]/$1=${!1}/g" "${settings_directory}/${settings_file}"`; then
          logger_func INFO "Changed setting for $1 to ${!1} in file ${settings_directory}/${settings_file}."
        else
          logger_func WARN "Failed to change setting for $1 in file ${settings_directory}/${settings_file}."
        fi
      else
        logger_func INFO "$1 is already set to ${!1} in file ${settings_directory}/${settings_file}, no need to update setting."
      fi
    else
      if `/bin/echo "$1=${!1}" >> "${settings_directory}/${settings_file}"`; then
        logger_func INFO "Added setting ${!1} for $1 to file ${settings_directory}/${settings_file}."
      else
        logger_func WARN "Failed to add setting ${!1} for $1 to file ${settings_directory}/${settings_file}."
      fi
    fi
  else
    logger_func WARN "Value for $1 is not correctly set in the script. Set it to 1 or 0."
  fi
}
### END OF FUNCTION DECLARATIONS

logger_func INFO "Starting Adobe Flash Update."

os_version=$( /usr/bin/sw_vers -productVersion | /usr/bin/sed 's/[.]/_/g' )
if [[ ! "${os_version}" =~ ^[0-9] ]]; then
  logger_func ERROR "Can't detect OS version."
fi

user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X ${os_version}) AppleWebKit/535.6.2 (KHTML, like Gecko) Version/5.2 Safari/535.6.2"

# TODO fix this mess...
plugin_name="NPAPI"
installed_app_path="/Library/Internet Plug-Ins/Flash Player.plugin"
latest_app_path="http://fpdownload2.macromedia.com/get/flashplayer/update/current/xml/version_en_mac_pep.xml"
update_plugin_func

plugin_name="PPAPI"
installed_app_path="/Library/Internet Plug-Ins/PepperFlashPlayer/PepperFlashPlayer.plugin"
latest_app_path="http://fpdownload2.macromedia.com/get/flashplayer/update/current/xml/version_en_mac_pep.xml"
update_plugin_func

cleanup_func 0