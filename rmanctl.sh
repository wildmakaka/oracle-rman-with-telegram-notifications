#!/bin/bash
# Name:       rmanctl.sh
# Comments:   Runs RMAN backup scripts.
#             Usage: rmnctl.sh {ORACLE_SID} Ex: rmnctl.sh HR
#
# 2018.05.05: Updated var usage. Fixed DOW bug.
# 2018.03.29: ME updated variable naming, added email notification.
# 2017.07.11: ME Fixed bug not deleting incr log on full backup day.
# 2017.06.28: ME Initial Version
# 2021.02.25 Add autocreation databse SID dir
# 2022.01.14 Add telegram notify instead email

# Standard Preamble
set -a; # Forces all vars to be exported (required to run from cron).
sScriptStarted=`date "+%Y-%m-%d %H:%M:%S"`
sScriptsDir="/home/oracle/scripts";cd $sScriptsDir
sFullName=`basename "$0"`;sBaseName=${sFullName%.*}
sBackupDir="/u01/app/oracle/RMAN";

# User Vars
#usrEmailList="ololo@rofl.com"; # Email addresses for status. Space Delimited.
usrRmanDir="/home/oracle/scripts/rman"; # Dir to RMAN backup scripts.
usrRmanLogs="$sScriptsDir/logs";    # Where to output log files.
usrFull=5;                          # Full backup day (Mon=1, Fri=5).
usrValidate=0;                      # If 1 then RMAN validate run after full backup.
ORACLE_HOME="/u01/app/oracle/product/19.0.0/dbhome_1";

# Telegram bot vars
TOKEN=<telegram API token>
CHAT_ID=<telegram chat ID>
URL="https://api.telegram.org/bot$TOKEN/sendMessage"


# Get CmdLine Parameter
if [ -z "$1" ]; then
   printf "Error: ORACLE_SID not specified.\n" | tee $usrRmanLogs/$sBaseName.err; exit
else
   ORACLE_SID="$1"
fi

# mkdir for ORACLE_SID
mkdir -p $sBackupDir/$ORACLE_SID

# System Vars
sDOW=$(date +%u)
sLine=`printf '=%.0s' {1..80}`
sSessionLog=$usrRmanLogs/$sBaseName.session.$ORACLE_SID.log
sHistLog=$usrRmanLogs/$sBaseName.hist.$ORACLE_SID.log

# Heading
clear
printf "$sScriptStarted\n"
printf "$sLine\n"
printf "ORACLE_SID:  $ORACLE_SID\n"
printf "usrRmanDir:  $usrRmanDir\n"
printf "usrRmanLogs: $usrRmanLogs\n"
printf "usrFull:     $usrFull\n"
printf "usrValidate: $usrValidate\n"
printf "$sLine\n"
printf "\n\n"
sleep 5

#Run RMAN Config
sRCFG=$usrRmanDir/rman.cfg.rmn
$ORACLE_HOME/bin/rman target / nocatalog @$sRCFG


# Process: RMAN Maintenance
printf "$sScriptStarted\n" > $sSessionLog
sRScript=$usrRmanDir/rman.maint.rmn
sRLog=$usrRmanLogs/rman.maint.$ORACLE_SID.log
printf "  Running: $sRScript \n" | tee -a $sSessionLog
$ORACLE_HOME/bin/rman target / nocatalog log=$sRLog @$sRScript


# Process: RMAN Backup
if [[ "$sDOW" == "$usrFull" ]]; then
   rm $usrRmanLogs/rman.maint./rman.backup_incr.$ORACLE_SID.log >/dev/null 2>&1
   sRScript="$usrRmanDir/rman.backup_full.rmn"
   sRLog="$usrRmanLogs/rman.maint./rman.backup_full.$ORACLE_SID.log"
else
   sRScript="$usrRmanDir/rman.backup_incr.rmn"
   sRLog="$usrRmanLogs/rman.backup_incr.$ORACLE_SID.log APPEND"
fi
printf "  Running: $sRScript \n" | tee -a $sSessionLog
$ORACLE_HOME/bin/rman target / nocatalog log=$sRLog @$sRScript

if [[ $? -eq 0 ]]; then
   sMsg="RMAN Backup: OK"
   printf "  $sMsg \n" | tee -a $sSessionLog
##   mail -s "$HOSTNAME.$sBaseName $ORACLE_SID (OK)" "$usrEmailList" <<< "$sMsg"
else
   sMsg="RMAN Backup: $HOSTNAME.$sBaseName $ORACLE_SID (FAILED)"
   printf "  $sMsg \n" | tee -a $sSessionLog
##   sMsgExt="$HOSTNAME.$sBaseName $ORACLE_SID (FAILED)" 
curl -s -X POST $URL -d chat_id=$CHAT_ID -d text="$sMsg"
fi


# Process: Validate
if [[ "$sDOW" == "$usrFull" ]]; then
   if [[ $usrValidate -eq 1 ]]; then
      sRScript="$usrRmanDir/rman.validate.rmn"
      sRLog="$usrRmanLogs/rman.validate.$ORACLE_SID.log"
      printf "  Running: $RSCRIPT \n" | tee -a $sSessionLog
      $ORACLE_HOME/bin/rman target / nocatalog log=$sRLog @$sRScript
      nStatus=$?
      printf "  RMAN Validate Exit Status: $nStatus \n" | tee -a $sSessionLog
   fi
fi


# End
sScriptEnded=`date "+%Y-%m-%d %H:%M:%S"`
printf "$sScriptEnded \n" >> $sSessionLog
cat $sSessionLog >> $sHistLog;printf "$sLine \n" >> $sHistLog
printf "\nScript Ended: $sScriptEnded \n"
