#!/bin/bash
#####################################################################################################
#
# ABOUT THIS PROGRAM
#
# NAME
#   SPSSLicenseUpdate.sh
#
# DESCRIPTION 
#   Activates IBM SPSS from JAMF/JSS or commandline.
#   This script is provided as is, use at your own risk :)
#
# AUTHOR
#   https://github.com/pigeonpilot
#
# SYNOPSIS
#   SPSSLicenseUpdate.sh [IBM SPSS version] [authorization code(s)]
#   SPSSLicenseUpdate.sh 24 12345678901234567890
#   Will activate version 24 with authorization-code 12345678901234567890
#
#   JAMF/JSS use parameters 4-11 for custom parameters.
#   Parameter 4 corresponds to SPSS version and should be 1-3 chars long and consist of 0-9.
#   Parameter 5 corresponds to autorization code(s) and should be atleast 20 chars long and consist of 0-9 a-z 
#   and : as separator when adding multiple codes.
#   Parameter 6 could be set to force to force activation of a license if the product is never previously activated, 
#   this string is case sensitive.
#
#   Running this script interactively:
#
#   sudo /bin/bash ./SPSSLicenseUpdate.sh 0 0 0 24 12345678901234567890 force
#
#   Or if not activating installations without licensekey already present.
#
#   sudo /bin/bash ./SPSSLicenseUpdate.sh 0 0 0 24 12345678901234567890
#
####################################################################################################

declare activation_error=""
declare app_path="/Applications/IBM/SPSS/Statistics/$4/SPSSStatistics.app"
# Threshold for license, if license expires within expire_threshold the script will request new authorization
declare -r expire_threshold="30"
declare java_bin=""
declare licenseactivator_bin="${app_path}/Contents/bin/licenseactivator"
declare -r log_file="/Library/Logs/SPSSLicenseUpdate.log"
declare -r spss_auth_server="lm.spss.com"
declare -r spss_auth_server_port="80"
declare JAVA_OPTS="$JAVA_OPTS -Djava.awt.headless=true"
# Disable dock icon for Java?
declare JAVA_TOOL_OPTIONS="-Dapple.awt.UIElement=true"
declare PATH=$PATH:"${app_path}/Contents/bin"
declare TERM=""


### START OF FUNCTION DECLARATIONS
logger_func () {
  /bin/echo "`/bin/date '+%Y-%m-%d %H:%M:%S'` `/usr/bin/basename "$0"` $1: $2" | /usr/bin/tee -a "${log_file}"
  if [ $1 = "ERROR" ]; then
    end_of_script 1
  fi
}

end_of_script () {
  logger_func INFO "End of script."
  exit "$1"
} 

check_license_server () {
if `/usr/bin/curl --fail --connect-timeout 10 -m 30 -s -A "${user_agent}" "${spss_auth_server}":"${spss_auth_server_port}" | /usr/bin/grep -Fq "SPSS License Server is Running"`; then
  logger_func INFO "IBM SPSS license activation server is accessible."
else
  logger_func ERROR "IBM SPSS license activation server is NOT accessible!"
fi
}

activate_license () {
check_license_server
cd "$app_path"/Contents/bin
activation_error=`"${java_bin}" -jar "${app_path}"/Contents/bin/licenseactivator.jar SILENTMODE CODES="$1"`
/bin/echo "activation error: ${activation_error}" 
/bin/echo "${activation_error}" | /usr/bin/grep -F "Authorization failed." > /dev/null
if [[ $? -eq 0 ]]; then
  failure_reason=`/bin/echo "${activation_error}" | /usr/bin/grep -F -A1 "Authorization failed." | /usr/bin/tail -n1`
  logger_func ERROR "License authorization failed. ${failure_reason}"
else
  /bin/echo "${activation_error}" | /usr/bin/grep -F "Authorization succeeded" > /dev/null
  if [[ $? -eq 0 ]]; then
    showlic_output=`"${app_path}/Contents/bin/showlic" -np -d "${app_path}/Contents/bin"`
    lic_expire_date="$(/bin/date -j -u -f "%d-%b-%Y" `echo "${showlic_output}" | /usr/bin/grep -F -A2 'Feature 1200 - IBM SPSS Statistics:' | /usr/bin/grep -F 'Expires on: ' | /usr/bin/cut -d ':' -f2 | /usr/bin/sed 's/[^0-9A-Za-z]//'` "+%s" | /usr/bin/sed 's/[^0-9]//g')"
    if  [ ! "${lic_expire_date}" -gt "653338918" ]; then
      logger_func ERROR "License authorization failed. Unable to update licensefile."
    else
      logger_func INFO "INFO: License authorization succeeded."
    fi
  else
    logger_func ERROR "Unknown error when activating the license."
  fi
fi
}

check_license () {
  lic_expire_date="$(/bin/date -j -u -f "%d-%b-%Y" `/bin/echo "${showlic_output}" | /usr/bin/grep -F -A2 'Feature 1200 - IBM SPSS Statistics:' | /usr/bin/grep -F 'Expires on: ' | /usr/bin/cut -d ':' -f2 | /usr/bin/sed 's/[^0-9A-Za-z]//'` "+%s" | /usr/bin/sed 's/[^0-9]//g')"
  if  [ ! "${lic_expire_date}" -gt "653338918" ]; then
    logger_func ERROR "lic_expire_date variable is invalid."
  fi

  cur_date="$(/bin/date -j -u "+%s" | /usr/bin/sed 's/[^0-9]//g')"
  if [ ! "${cur_date}" -gt "653338918" ]; then
    logger_func ERROR "cur_date variable is invalid."
  fi

  if [ `/bin/echo "(${lic_expire_date} - ${cur_date})/(60*60*24)" | /usr/bin/bc` -lt "${expire_threshold}"  ]; then
    logger_func INFO "License expires `/bin/date -j -u -f "%s" "${lic_expire_date}"` which is in less than ${expire_threshold} days, will try to activate a new license."
    activate_license
  else
    logger_func INFO "License expires `/bin/date -j -u -f "%s" "${lic_expire_date}"` which is in more than "${expire_threshold}" days, activation of a new license is not necessary."
  fi
}
### END OF FUNCTION DECLARATIONS

logger_func INFO "Starting SPSS License Update."

os_version=$( /usr/bin/sw_vers -productVersion | /usr/bin/sed 's/[.]/_/g' )
if [[ ! "${os_version}" =~ ^[0-9] ]]; then
  logger_func ERROR "Can't detect OS version."
fi

user_agent="Mozilla/5.0 (Macintosh; Intel Mac OS X ${os_version}) AppleWebKit/535.6.2 (KHTML, like Gecko) Version/5.2 Safari/535.6.2"
if [ "$#" -lt 5 ]; then
    logger_func ERROR "To few parameters passed to script."
fi

if [[ "${#4}" -gt 0 && "${#4}" -lt 4 && "${4//[^0-9]/}" =~ ^[0-9]+$ ]]; then
  logger_func INFO "Parameter for version number is ok."
else
  logger_func ERROR "Parameter for version number is NOT ok!"
fi

if [[ "${#5}" -ge 20 && "$5" =~ ^[0-9a-z:]+$ ]]; then
  logger_func INFO "Parameter for authorization code is ok."
else
  logger_func ERROR "Parameter for authorization code is NOT ok!"
fi

if  [[ "${6}" != "force" && "${6}" != "" ]]; then
  logger_func ERROR "Parameter for force installation is NOT ok!"
fi

if [ ! -f "${app_path}/Contents/Info.plist" ]; then
  logger_func ERROR "Application path for IBM SPSS version $4 does NOT exist?"
fi

java_bin=`/usr/bin/find "${app_path}" -type f -perm +111 -name java | /usr/bin/tail -n1`
if [ "${java_bin}" = "" ];then
  logger_func ERROR "Java not found!"
fi

if [ -f "${app_path}/Contents/bin/lservrc" ]; then
  showlic_output=`"${app_path}/Contents/bin/showlic" -np -d "${app_path}/Contents/bin"`
  case "${showlic_output}" in
    *"No licenses found for IBM SPSS Statistics"*)
      logger_func INFO "No license found."
    ;;
    *"A temporary license has expired"*)
      logger_func INFO "A temporary license has expired."
    ;;
    *"Feature 1200 - IBM SPSS Statistics:"*"Temporary"*)
      logger_func INFO "A temporary license is installed."
    ;;
    *"Feature 1200 - IBM SPSS Statistics:"*"Network license"*)
      logger_func INFO "A Network license is installed."
    ;;
    *"Feature 1200 - IBM SPSS Statistics:"*"Local license for version"*)
      logger_func INFO "A local license is installed."
      check_license $5
    ;;
    *)
      logger_func ERROR "Unknown license."
  esac
else
  if [[ "${6}" == "force" ]]; then
    logger_func INFO "lservrc is missing and force installation is set, will try to activate license."
    activate_license $5
  else
    logger_func ERROR "lservrc is missing and force installation is not set."
  fi
end_of_script 0  
fi