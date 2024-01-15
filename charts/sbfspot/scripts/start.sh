#!/bin/sh

confdir=/etc/sbfspot
homedir=/usr/local/bin/sbfspot.3
datadir=/var/sbfspot
sbfspotbinary=""
sbfspotuploadbinary=""
sbfspot_cfg_file=""
sbfspot_upload_cfg_file=""
sbfspot_options=""

getConfigValue() {
    key=$1
    echo "$sbfspot_cfg_file" | grep -e "^$key=" | cut -f 2 -d "=" | sed 's/[ 	]*$//' # search for key, get value, delete invisible chars at the end
}

setConfigValue() {
    key=$1
    value=$2
    temp_value="$(getConfigValue "$key")"
    if [ -n "$temp_value" ]; then   # key found, so update new value
        echo "$sbfspot_cfg_file" | sed "/^$key=.*/c $key=$value" > $confdir/SBFspot.cfg
    else
        temp_value="$(getConfigValue "#$key")"  # search for inactive key
        if [ -n "$temp_value" ]; then  # append key=value after the first match
            echo "$sbfspot_cfg_file" | sed "0,/^#$key/!b;//a$key=$value" > $confdir/SBFspot.cfg
        else
            temp_value="$(getConfigValue "# $key")"   # no inactive key found, test again with space after hashtag
            if [ -n "$temp_value" ]; then  # append key=value after the first match
                echo "$sbfspot_cfg_file" | sed "0,/^# $key/!b;//a$key=$value" > $confdir/SBFspot.cfg
            else
                echo "Cannot find the option \"$key\" in SBFspot.cfg. Appending the option at the end of the file."
                echo "$sbfspot_cfg_file" | sed "\$a $key=$value" > $confdir/SBFspot.cfg
            fi
        fi
    fi
    readConfig
}

readConfig() {
    sbfspot_cfg_file=$( cat $confdir/SBFspot.cfg | dos2unix -u )
}

getUploadConfigValue() {
    key=$1
    echo "$sbfspot_upload_cfg_file" | grep -e "^$key=" | cut -f 2 -d "=" | sed 's/[ 	]*$//' # search for key, get value, delete invisible chars at the end
}

setUploadConfigValue() {
    key=$1
    value=$2
    temp_value="$(getUploadConfigValue "$key")"
    if [ -n "$temp_value" ]; then   # key found, so update new value
        echo "$sbfspot_upload_cfg_file" | sed "/^$key=.*/c $key=$value" > $confdir/SBFspotUpload.cfg
    else
        temp_value="$(getUploadConfigValue "#$key")"  # search for inactive key
        if [ -n "$temp_value" ]; then  # append key=value after the first match
            echo "$sbfspot_upload_cfg_file" | sed "0,/^#$key/!b;//a$key=$value" > $confdir/SBFspotUpload.cfg
        else
            temp_value="$(getUploadConfigValue "# $key")"   # no inactive key found, test again with space after hashtag
            if [ -n "$temp_value" ]; then  # append key=value after the first match
                echo "$sbfspot_upload_cfg_file" | sed "0,/^# $key/!b;//a$key=$value" > $confdir/SBFspotUpload.cfg
            else
                echo "Cannot find the option \"$key\" in SBFspotUpload.cfg. Appending the option at the end of the file."
                echo "$sbfspot_upload_cfg_file" | sed "\$a $key=$value" > $confdir/SBFspotUpload.cfg
            fi
        fi
    fi
    readUploadConfig
}

readUploadConfig() {
    sbfspot_upload_cfg_file=$( cat $confdir/SBFspotUpload.cfg | dos2unix -u )
}

checkSBFConfig() {
    ERROR_FLAG=0
    if [ -r $confdir/SBFspot.cfg ]; then
        readConfig
        if [ -n "$CSV_STORAGE" ] && [ $CSV_STORAGE -eq 1 ]; then
            if [ `getConfigValue CSV_Export` -eq 0 ]; then
                if [ -w $confdir/SBFspot.cfg ]; then
                    setConfigValue "CSV_Export" "1"
                    echo "Wrong CSV_Export value in SBFspot.cfg. I change it to 1."
                else
                    echo "$confdir/SBFspot.cfg is not writeable by User with ID `id -u sbfspot`."
                    echo "Please change file permissions of SBFspot.cfg or ensure, that the \"CSV_Export\""
                    echo "value is 1"
                    ERROR_FLAG=1
                fi
            fi
        fi
        if [ `getConfigValue CSV_Export` -eq 1 ]; then   # if CSV_Export=1 then OutputPath and OutputPathEvents must point to /var/sbfspot
            if [ -w $confdir/SBFspot.cfg ]; then
                if ! `getConfigValue OutputPath | grep -q -e "^/var/sbfspot$"` && \
                        ! `getConfigValue OutputPath | grep -q -e "^/var/sbfspot/"`; then
                    setConfigValue "OutputPath" "$datadir/%Y"
                    echo "Wrong OutputPath value in SBFspot.cfg. I change it to \"$datadir/%Y\""
                fi

                if ! `getConfigValue OutputPathEvents | grep -q -e "^/var/sbfspot$"` && \
                        ! `getConfigValue OutputPathEvents | grep -q -e "^/var/sbfspot/"`; then
                    setConfigValue "OutputPathEvents" "$datadir/%Y/Events"
                    echo "Wrong OutputPathEvents value in SBFspot.cfg. I change it to \"$datadir/%Y/Events\""
                fi
            else
                echo "$confdir/SBFspot.cfg is not writeable by User with ID `id -u sbfspot`."
                echo "Please change file permissions of SBFspot.cfg or ensure, that the \"OutputPath\" and \"OutputPathEvents\" Options"
                echo "point to the Directory $datadir/..."
                ERROR_FLAG=1
            fi

            # check if data directory is writeable
            if [ ! -w $datadir ]; then
                echo "Mapped Data directory is not writeable for user with ID `id -u sbfspot`."
                echo "Please change file permissions accordingly and restart the container."
                exit 1
            fi
        fi
        if [ -n "$MQTT_ENABLE" ] && [ $MQTT_ENABLE -eq 1 ]; then
            if ! `getConfigValue MQTT_Publisher | grep -q -e "^/usr/bin/mosquitto_pub"`; then
                setConfigValue "MQTT_Publisher" "/usr/bin/mosquitto_pub"
                echo "Wrong MQTT_Publisher value in SBFspot.cfg corrected."
            fi
            if `getConfigValue MQTT_Host | grep -q -e "^test.mosquitto.org"`; then
                echo "Warning: Please configure the \"MQTT_Host\" value in SBFspot.cfg."
            fi
        fi
        if [ "$DB_STORAGE" = "sqlite" ]; then
            if [ ! -e $datadir/sbfspot.db ]; then # check if database file exists
                if [ -z "$INIT_DB" ] || [ $INIT_DB -ne 1 ]; then
                    echo "SQLite database file under \"$datadir/sbfspot.db\" does not exist. Please initialize the database."
                    exit 1
                fi
            else
                if [ ! -w $datadir/sbfspot.db ]; then
                    echo "SQLite database file under \"$datadir/sbfspot.db\" is not writeable for user with ID `id -u sbfspot`."
                    echo "Please change file permissions accordingly and restart the container."
                    ERROR_FLAG=1
                fi
                if [ ! -r $datadir/sbfspot.db ]; then
                    echo "SQLite database file under \"$datadir/sbfspot.db\" is not readable for user with ID `id -u sbfspot`."
                    echo "Please change file permissions accordingly and restart the container."
                    ERROR_FLAG=1
                fi
            fi

            if [ -w $confdir/SBFspot.cfg ]; then # check if SQLite DB is correctly configured in SBFspot.cfg
                if ! `getConfigValue SQL_Database | grep -q -e "^$datadir/sbfspot.db"`; then
                    setConfigValue "SQL_Database" "$datadir/sbfspot.db"
                    echo "Wrong SQL_Database value in SBFspot.cfg. I change it to \"$datadir/sbfspot.db\""
                fi
            else
                echo "$confdir/SBFspot.cfg is not writeable by User with ID `id -u sbfspot`."
                echo "Please change file permissions of SBFspot.cfg or ensure, that the \"SQL_Database\" option"
                echo "points to the file $datadir/sbfspot.db"
                ERROR_FLAG=1
            fi
        fi
    else
        echo "$confdir/SBFspot.cfg is not readable by user with ID `id -u sbfspot`."
        echo "Please change file permissions accordingly and restart the container."
        exit 1
    fi

    if [ $ERROR_FLAG -eq 1 ]; then
        echo "Please configure the listed value(s) and restart the container."
        exit 1
    fi
}

checkSBFUploadConfig() {
    ERROR_FLAG=0
        if [ -r $confdir/SBFspotUpload.cfg ]; then
            readUploadConfig
            tempValue=`getUploadConfigValue PVoutput_SID`
            if [ -z $tempValue ];then
                echo "Please set the \"PVoutput_SID\" option in \"SBFspotUpload.cfg\"."
                echo "Otherwise the production data can't be uploaded to PVoutput."
                ERROR_FLAG=1
            fi
            tempValue=`getUploadConfigValue PVoutput_Key`
            if [ -z $tempValue ];then
                echo "Please set the \"PVoutput_Key\" option in \"SBFspotUpload.cfg\"."
                echo "Otherwise the production data can't be uploaded to PVoutput."
                ERROR_FLAG=1
            fi

            if [ "$DB_STORAGE" = "sqlite" ]; then # check if SQLite DB is correctly configured in SBFspot.cfg
                if ! `getUploadConfigValue SQL_Database | grep -q -e "^$datadir/sbfspot.db"`; then
                    if [ -w $confdir/SBFspotUpload.cfg ]; then
                        setUploadConfigValue "SQL_Database" "$datadir/sbfspot.db"
                        echo "Wrong SQL_Database value in SBFspotUpload.cfg. I change it to \"$datadir/sbfspot.db\""
                    else
                        echo "$confdir/SBFspotUpload.cfg is not writeable by User with ID `id -u sbfspot`."
                        echo "Please change file permissions of SBFspotUpload.cfg or ensure, that the \"SQL_Database\" option"
                        echo "points to the file $datadir/sbfspot.db"
                        ERROR_FLAG=1
                    fi
                fi
            fi
        else
            echo "$confdir/SBFspotUpload.cfg is not readable by user with ID `id -u sbfspot`."
            echo "Please change file permissions accordingly and restart the container."
            exit 1
        fi

    if [ $ERROR_FLAG -eq 1 ]; then
        echo "Please configure the listed value(s) and restart the container."
        exit 1
    fi
}

setupSBFspotOptions() {
    if [ -n "$SBFSPOT_ARGS" ]; then
        sbfspot_options=" $SBFSPOT_ARGS "
    fi
    if [ -n "$FORCE" ] && [ $FORCE -eq 1 ]; then
        sbfspot_options="$sbfspot_options -finq"
    fi
    if [ -n "$FINQ" ] && [ $FINQ -eq 1 ]; then
        sbfspot_options="$sbfspot_options -finq"
    fi
    if [ -n "$QUIET" ] && [ $QUIET -eq 1 ]; then
        sbfspot_options="$sbfspot_options -q"
    fi
    if [ -n "$MQTT_ENABLE" ] && [ $MQTT_ENABLE -eq 1 ]; then
        sbfspot_options="$sbfspot_options -mqtt"
    fi
}


selectSBFspotBinary() {
    if [ -n "$ENABLE_SBFSPOT" ] && [ $ENABLE_SBFSPOT -ne 0 ]; then
        if [ -z "$DB_STORAGE" ]; then
            sbfspotbinary=SBFspot_nosql
        elif [ "$DB_STORAGE" = "sqlite" ]; then
            sbfspotbinary=SBFspot_sqlite
        elif [ "$DB_STORAGE" = "mysql" ]; then
            sbfspotbinary=SBFspot_mysql
        elif [ "$DB_STORAGE" = "mariadb" ]; then
            sbfspotbinary=SBFspot_mariadb
        else
            echo "storage type \"$DB_STORAGE\" not available. Options: sqlite | mysql | mariadb"
            exit 1
        fi

        checkSBFConfig
    fi
}

selectSBFspotUploadBinary() {
    if [ -n "$ENABLE_SBFSPOT_UPLOAD" ] && [ $ENABLE_SBFSPOT_UPLOAD -ne 0 ]; then
        if [ "$DB_STORAGE" = "sqlite" ]; then
            sbfspotuploadbinary=SBFspotUploadDaemon_sqlite
        elif [ "$DB_STORAGE" = "mysql" ]; then
            sbfspotuploadbinary=SBFspotUploadDaemon_mysql
        elif [ "$DB_STORAGE" = "mariadb" ]; then
            sbfspotuploadbinary=SBFspotUploadDaemon_mariadb
        else
            echo "storage type \"$DB_STORAGE\" not available for SBFspotUploadDaemon. Options: sqlite | mysql | mariadb"
            exit 1
        fi

        checkSBFUploadConfig
    fi
}

checkStorageType() {
    if [ -z "$DB_STORAGE" ] && ( [ -z "$CSV_STORAGE" ] || [ $CSV_STORAGE -ne 1 ] ) && ( [ -z "$MQTT_ENABLE" ] || [ $MQTT_ENABLE -ne 1 ] ); then
        echo "Error, no Data Output is selected. Please configure at least one of the options: DB_STORAGE, CSV_STORAGE or MQTT_ENABLE"
        exit 1
    fi
}

checkNoServiceSelected() {
    if ( [ -z "$ENABLE_SBFSPOT" ] || [ $ENABLE_SBFSPOT -eq 0 ] ) && ( [ -z "$ENABLE_SBFSPOT_UPLOAD" ] || [ $ENABLE_SBFSPOT_UPLOAD -eq 0 ] ); then
        if ( [ -n "$INIT_DB" ] && [ $INIT_DB -ne 1 ] ); then
            echo "Warning: Neither SBFspot nor SBFspotUploadDaemon were enabled"
            echo "Enable at least one by setting ENABLE_SBFSPOT or ENABLE_SBFSPOT_UPLOAD environment variable to 1"
            exit 1
        else
            checkSBFConfig   // if no service but $INIT_DB is selected, checkSBFConfig has to be called
        fi
    fi
}

setTimezone() {
    if [ -z "$TZ" ]; then
        tz=$(getConfigValue "Timezone")
        if [ -z "$tz" ]; then
            echo "Error: Timezone not configured."
            exit 1
        else
            echo "Setting Timezone from config to $tz"
            export TZ=$tz
        fi
    fi
}

############################################################################################################################################

# Scriptstart

############################################################################################################################################

checkStorageType

checkNoServiceSelected

selectSBFspotBinary

selectSBFspotUploadBinary

setTimezone

# Start SBFspotUploadDaemon in background
if [ -n "$sbfspotuploadbinary" ]; then
  if [ -n "$sbfspotbinary" ]; then
    $homedir/$sbfspotuploadbinary -c $confdir/SBFspotUpload.cfg &
  else
    $homedir/$sbfspotuploadbinary -c $confdir/SBFspotUpload.cfg
  fi
fi

if [ -n "$sbfspotbinary" ]; then
  # add Options to SBFspot cmdline
  setupSBFspotOptions

  if [ $SBFSPOT_INTERVAL -lt 60 ]; then
      SBFSPOT_INTERVAL=60;
      echo "SBFSPOT_INTERVAL is very short. It will be set to 60 seconds."
  fi

  while true; do
      timeout --foreground 180 $homedir/$sbfspotbinary $sbfspot_options -cfg$confdir/SBFspot.cfg

      # if QUIET SBFspot Option is set, produce less output
      if echo $sbfspot_options | grep -q "\-q"; then
          DELTA=$((60 - SBFSPOT_INTERVAL / 60))
          if [ $(date +%H) -eq 23 ] && [ $(date +%M) -ge $DELTA ];then   # last entry of a day
              if [ $(date +%u) -eq 7 ];then   # sunday
                  echo -n "week "
                  date +%W\ %Y
              else                           # all other days
                  date +%a
              fi
          else
              echo -n "."
          fi
          sleep $SBFSPOT_INTERVAL
      else
          date
          echo "Waiting $SBFSPOT_INTERVAL seconds..."
          sleep $SBFSPOT_INTERVAL
      fi
  done
fi