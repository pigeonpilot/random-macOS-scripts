#!/bin/bash
#####################################################################################################
#
# ABOUT THIS PROGRAM
#
# NAME
#   FirefoxUpdate.sh
#
# DESCRIPTION 
#   Updates Firefox to latest version on Mac OS.
#   Inspired by https://www.jamf.com/jamf-nation/discussions/26076/mozilla-firefox-esr-update-script
#   This script is provided as is, use at your own risk :)
#
# AUTHOR
#   https://github.com/pigeonpilot
#
# SYNOPSIS
#   sudo ./FirefoxUpdate.sh
#
####################################################################################################

set -u

declare app_mount=""
declare app_release=""
declare dmg_file=""
declare exit_status="1"
declare -r firefox_bin="/Applications/Firefox.app/Contents/MacOS/firefox"
declare installed_app_ver=""
declare -r jamfHelper_bin="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
declare latest_ver=""
declare locale_lang=""
declare -r log_file="/Library/Logs/FirefoxUpdateScript.log"
declare os_version=""
declare systemLocale=""

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

func_sort_app_ver () {
  # sort -r means bleeding edge version, remove -r to use older tree
  IFS=' ' read -a ver_array <<< "$1"
  IFS=$'\n' sorted_ver_array=($(/usr/bin/sort -r <<<"${ver_array[*]}"))
  unset IFS
  latest_app_ver="${sorted_ver_array[0]}"
}
### END OF FUNCTION DECLARATIONS

logger_func INFO "Starting FirefoxUpdate."

# TODO Convert to functions...
if [ '`/usr/bin/uname -p`'="i386" -o '`/usr/bin/uname -p`'="x86_64" ]; then

  if [ -e "/Applications/Firefox.app" ]; then

    os_version=$( /usr/bin/sw_vers -productVersion | /usr/bin/sed 's/[.]/_/g' )
    if [[ ! "${os_version}" =~ ^[0-9] ]]; then
      logger_func ERROR "Can't detect OS version"
    fi

    systemLocale=`/usr/bin/osascript -e 'user locale of (get system info)' | /usr/bin/sed 's/[^a-z]//g'`
    logger_func INFO "System language detected as $systemLocale"

    user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X ${os_version}) AppleWebKit/535.6.2 (KHTML, like Gecko) Version/5.2 Safari/535.6.2"

    installed_app_ver=`/usr/bin/defaults read /Applications/Firefox.app/Contents/Info CFBundleShortVersionString`
    if [[ ! "${installed_app_ver}" =~ ^[0-9] ]];then
      logger_func ERROR "Can't detect version of installed application"
    fi

    if [ -e "/Applications/Firefox.app/Contents/MacOS/platform.ini" ]; then
      if [ "`/usr/bin/printf "${installed_app_ver}\n10" | /usr/bin/sort -n | /usr/bin/tail -n1`" == "10" ]; then
        app_release="release"
      else
        app_release=`/usr/bin/grep SourceRepository /Applications/Firefox.app/Contents/MacOS/platform.ini | /usr/bin/rev | /usr/bin/cut -d "-" -f 1 |/usr/bin/rev`
      fi
    fi

    if [ -e "/Applications/Firefox.app/Contents/MacOS/defaults/pref/firefox-l10n.js" ]; then
      app_release="release"
      locale_lang=`/usr/bin/grep "general.useragent.locale" /Applications/Firefox.app/Contents/MacOS/defaults/pref/firefox-l10n.js | /usr/bin/cut -d "," -f 2 | /usr/bin/sed 's/[ ");]*//g'`
    fi

    if [ -e "/Applications/Firefox.app/Contents/Resources/application.ini" ]; then
      app_release=`/usr/bin/grep SourceRepository /Applications/Firefox.app/Contents/Resources/application.ini | /usr/bin/rev | /usr/bin/cut -d "-" -f 1 | /usr/bin/rev`
    fi

    if [ -e "/Applications/Firefox.app/Contents/MacOS/omni.jar" ]; then
      locale_lang=`/usr/bin/unzip -p /Applications/Firefox.app/Contents/MacOS/omni.jar */firefox-l10n.js 2>/dev/null| /usr/bin/grep "general.useragent.locale" | /usr/bin/cut -d "," -f 2 | /usr/bin/sed 's/[ ");]*//g'`
      if [ ! -z "${locale_lang}" ]; then
        logger_func INFO "Detected locale ${locale_lang} from firefox-l10n.js in archive omni.jar"
      fi
    fi

    if [ -e "/Applications/Firefox.app/Contents/MacOS/omni.ja" ]; then
      locale_lang=`/usr/bin/unzip -p /Applications/Firefox.app/Contents/MacOS/omni.ja */firefox-l10n.js 2>/dev/null| /usr/bin/grep "general.useragent.locale" | /usr/bin/cut -d "," -f 2 | /usr/bin/sed 's/[ ");]*//g'`
      if [ -z "${locale_lang}" ]; then
        locale_lang=`/usr/bin/unzip -p /Applications/Firefox.app/Contents/MacOS/omni.ja */chrome.manifest 2>/dev/null| /usr/bin/grep -E "^locale global " | /usr/bin/cut -d " " -f 3`
        logger_func INFO "Detected locale ${locale_lang} from chrome.manifest in archive omni.ja"
      else
        logger_func INFO "Detected locale ${locale_lang} from firefox-l10n.js in archive omni.ja"
      fi
    fi

    if [ -e "/Applications/Firefox.app/Contents/Resources/omni.ja" ]; then
      locale_lang=`/usr/bin/unzip -p /Applications/Firefox.app/Contents/Resources/omni.ja */chrome.manifest 2>/dev/null| /usr/bin/grep -E "^locale global " | /usr/bin/cut -d " " -f 3`

      if [ ! -z "${locale_lang}" ]; then
        logger_func INFO "Detected locale ${locale_lang} from chrome.manifest in archive omni.ja"
      fi
    fi

    if [ -e "/Applications/Firefox.app/Contents/MacOS/defaults/pref/firefox-l10n.js" ]; then
      locale_lang=`/usr/bin/grep "general.useragent.locale" /Applications/Firefox.app/Contents/MacOS/defaults/pref/firefox-l10n.js | /usr/bin/cut -d "," -f 2 | /usr/bin/sed 's/[ ");]*//g'`
      logger_func INFO "Detected locale ${locale_lang} from firefox-l10n.js"
    fi

    if [ -z "${locale_lang}" ]; then
      logger_func ERROR "Can't detect locale for Mozilla Firefox."
    fi
    case "${app_release}" in
      *esr*)
        latest_app_ver_string=`/usr/bin/curl --fail --connect-timeout 10 -m 300 -s "https://www.mozilla.org/sv-SE/firefox/new/" | /usr/bin/grep -o 'data-esr-versions=[^a-z]*' | /usr/bin/sed -e 's/\"//g' | /usr/bin/cut -d "=" -f2 | /usr/bin/sed -e 's/[[:blank:]]*$//'`
        func_sort_app_ver "${latest_app_ver_string//[!0-9. ]/}"
        latest_app_ver="$latest_app_ver"esr

        if [[ "${latest_app_ver}" =~ ^[0-9]+ ]]; then
          logger_func INFO "Mozilla Firefox ESR release version ${installed_app_ver} with locale ${locale_lang} is installed, latest version available is ${latest_app_ver//[a-z]/}"
        else
          logger_func ERROR "cannot detect latest Mozilla Firefox version available."
        fi
        ;;
      release)
        latest_app_ver_string=`/usr/bin/curl --fail --connect-timeout 10 -m 300 -s "https://www.mozilla.org/sv-SE/firefox/new/" | /usr/bin/grep -o 'data-latest-firefox=[^a-z]*' | /usr/bin/sed -e 's/\"//g' | /usr/bin/cut -d "=" -f2 | /usr/bin/sed -e 's/[[:blank:]]*$//'`
        func_sort_app_ver "${latest_app_ver_string//[!0-9. ]/}"

        if [[ "${latest_app_ver}" =~ ^[0-9]+ ]]; then
          logger_func INFO "Mozilla Firefox non-ESR release version ${installed_app_ver} with locale ${locale_lang} is installed, latest version available is $latest_app_ver"
        else
          logger_func ERROR "can't detect latest Mozilla Firefox version available."
        fi
        ;;
      *)
        logger_func ERROR "can't detect Mozilla Firefox release type."
    esac

    if [ "${installed_app_ver}" != "${latest_app_ver//[a-z]/}" ]; then

      download_url="https://download-installer.cdn.mozilla.net/pub/firefox/releases/${latest_app_ver}/mac/${locale_lang}/Firefox%20${latest_app_ver}.dmg"

      logger_func INFO "Download URL: ${download_url}"
      logger_func INFO "Downloading version ${latest_app_ver//[a-z]/} with locale ${locale_lang}."

      dmg_file="`/usr/bin/mktemp -q /tmp/XXXXXXXXXXXXXXXXXXXXXXXXX`"
      if [ $? -ne 0 ]; then
        logger_func ERROR "Can't create temp file, exiting..."
      fi
      
      /usr/bin/curl --fail --connect-timeout 10 -m 300 -s -o "${dmg_file}" "${download_url}"
      if [ $? -eq 0 ]; then
        logger_func INFO "Successfully downloaded ${download_url}"
      else
        logger_func ERROR "when downloading ${download_url}"
      fi

      /bin/echo "`/bin/date`: INFO: Mounting installer disk image." >> "${log_file}"

      app_mount="`/usr/bin/hdiutil attach "${dmg_file}" -nobrowse | /usr/bin/tail -n1 | /usr/bin/cut -f 3`"
      if [ ! $? -eq 0 ]; then
        logger_func ERROR "Failed to mount installer disk image."
      fi

      /bin/rm -rf "/Applications/Firefox.app"
      if [ ! $? -eq 0 ]; then
        logger_func ERROR "Failed to delete applicationfolder."
      fi

      logger_func INFO "INFO: Installing update."

      /usr/bin/ditto -rsrc "${app_mount}/Firefox.app" "/Applications/Firefox.app" > /dev/null 2>&1
      if [ ! $? -eq 0 ]; then
        logger_func ERROR "Installation failed."
      fi

      newly_installed_app_ver=`/usr/bin/defaults read /Applications/Firefox.app/Contents/Info CFBundleShortVersionString`

      if [ "${latest_app_ver//[a-z]/}" = "${newly_installed_app_ver}" ]; then
        if [ -e "${jamfHelper_bin}" ] && [ `/bin/ps -e | /usr/bin/pgrep -f "${firefox_bin}" | /usr/bin/wc -c` -gt 0 ]; then
          case "$systemLocale" in
            sv)
              "${jamfHelper_bin}" -heading "Mozilla Firefox har uppdaterats." -windowType utility -windowPosition ur -icon "/Applications/Firefox.app/Contents/Resources/firefox.icns" -description "Mozilla Firefox har uppdaterats från version $installed_app_ver till version $newly_installed_app_ver. Starta om applikationen Mozilla Firefox för att aktivera den nya versionen." -alignDescription natural -button1 "OK"  > /dev/null 2>&1 &
              logger_func INFO "JamfHelper-message in swedish was displayed."
              ;;
            en)
              "${jamfHelper_bin}" -heading "Mozilla Firefox has been updated." -windowType utility -windowPosition ur -icon "/Applications/Firefox.app/Contents/Resources/firefox.icns" -description "Mozilla Firefox has been updated from version $installed_app_ver to version $newly_installed_app_ver. Restart the application Mozilla Firefox to activate the new version." -alignDescription natural -button1 "OK"  > /dev/null 2>&1 &
              logger_func INFO "JamfHelper-message in english was displayed."
              ;;
            *)
              logger_func WARN "Can't detect systemlanguage, jamfHelper-message will not be displayed."
              ;;
          esac
        else
          if [ ! -e "${jamfHelper_bin}" ]; then
            logger_func WARN "jamfHelper is not installed, jamfHelper-message will not be displayed."
          fi
        fi
        logger_func INFO "Mozilla Firefox has successfully been updated to version ${newly_installed_app_ver}."
      else
        logger_func ERROR "Mozilla Firefox update unsuccessful."
      fi
    else
      logger_func INFO "Mozilla Firefox version ${installed_app_ver} is already up to date."
    fi
  else
    logger_func ERROR "Mozilla Firefox does not seem to be installed?"
  fi
  cleanup_func 0
else
  logger_func ERROR "This script is for Intel Macs only."
fi