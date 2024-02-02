#!/bin/sh

set -e

confdir=/etc/sbfspot
homedir=/usr/local/bin/sbfspot.3
datadir=/var/sbfspot
sbfspot_cfg_file=""

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


initDatabase() {
    if [ "$DB_STORAGE" = "sqlite" ]; then
          # check if data directory is writeable
          if [ ! -w $datadir ]; then
              echo "Mapped Data directory is not writeable for user with ID `id -u sbfspot`."
              echo "Please change file permissions accordingly and restart the container."
              exit 1
          fi
          sqlite3 $datadir/sbfspot.db < $homedir/CreateSQLiteDB.sql
        exit 0
    elif [ "$DB_STORAGE" = "mysql" ] || [ "$DB_STORAGE" = "mariadb" ]; then
        HOST=$(getConfigValue SQL_Hostname)
        DB=$(getConfigValue SQL_Database)
        USER=$(getConfigValue SQL_Username)
        PW=$(getConfigValue SQL_Password)

        ERROR_FLAG=0
        if [ -z "$HOST" ]; then
            ERROR_FLAG=1
            echo "No SQL_Hostname configured in SBFspot.cfg."
        fi
        if [ -z "$DB" ]; then
            ERROR_FLAG=1
            echo "No SQL_Database configured in SBFspot.cfg."
        fi
        if [ -z "$USER" ]; then
            ERROR_FLAG=1
            echo "No SQL_Username configured in SBFspot.cfg."
        fi
        if [ -z "$PW" ]; then
            ERROR_FLAG=1
            echo "No SQL_Password configured in SBFspot.cfg."
        fi
        if [ -z "$DB_ROOT_USER" ]; then
            ERROR_FLAG=1
            echo "Add \"DB_ROOT_USER\" Environment Variable with appropriate value e.g. \"root\" to your docker run command."
        fi
        if [ -z "$DB_ROOT_PW" ]; then
            ERROR_FLAG=1
            echo "Add \"DB_ROOT_PW\" Environment Variable with appropriate value to your docker run command."
        fi
        if [ $ERROR_FLAG -eq 1 ]; then
            echo "Please configure the listed value(s) and restart the container."
            exit 1
        fi

        if `mysql -h $HOST --protocol=TCP -u $DB_ROOT_USER -p$DB_ROOT_PW < $homedir/CreateMySQLDB.sql`; then
            echo "Database, tables and views created."
        else
            cp $homedir/CreateMySQLDB.sql $datadir
            echo "Error creating SBFspot Database, tables and views. Please manually add the file \"CreateMySQLDB.sql\""
            echo "(located in SBFspots data directory) to your Database, if the Database does not exist yet."
            exit 1
        fi
        SQL_USER_ADD="CREATE USER '$USER' IDENTIFIED BY '$PW';"
        SQL_USER_CHANGE="ALTER USER '$USER' IDENTIFIED BY '$PW';"
        SQL_GRANT1="GRANT INSERT,SELECT,UPDATE ON SBFspot.* TO '$USER';"
        SQL_GRANT2="GRANT DELETE,INSERT,SELECT,UPDATE ON SBFspot.MonthData TO '$USER';"

        if `mysql -h $HOST --protocol=TCP -u $DB_ROOT_USER -p$DB_ROOT_PW -e "SELECT User FROM mysql.user;" | grep -q -e $USER`; then
            echo "User $USER exists in Database, only changing password"
            mysql -h $HOST --protocol=TCP -u $DB_ROOT_USER -p$DB_ROOT_PW -e "$SQL_USER_CHANGE"
        else
            if `mysql -h $HOST --protocol=TCP -u $DB_ROOT_USER -p$DB_ROOT_PW -e "$SQL_USER_ADD"`; then
                echo "Database User created"
            fi
        fi
        if `mysql -h $HOST --protocol=TCP -u $DB_ROOT_USER -p$DB_ROOT_PW -e "$SQL_GRANT1"`; then
            echo "Following rights for User $USER set"
            echo "$SQL_GRANT1"
        fi
        if `mysql -h $HOST --protocol=TCP -u $DB_ROOT_USER -p$DB_ROOT_PW -e "$SQL_GRANT2"`; then
            echo "Following rights for User $USER set"
            echo "$SQL_GRANT2"
        fi
        touch $datadir/sbfspot.db
        exit 0
    elif [ "$DB_STORAGE" != "sqlite" ] && [ "$DB_STORAGE" != "mysql" ] && [ "$DB_STORAGE" != "mariadb" ]; then
        echo "storage type \"$DB_STORAGE\" not available. Options: sqlite | mysql | mariadb"
        exit 1
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

############################################################################################################################################

# Scriptstart

############################################################################################################################################

checkStorageType

checkNoServiceSelected

# initialize Database
if [ -n "$INIT_DB" ] && [ $INIT_DB -eq 1 ]; then
  if [ ! -e $datadir/sbfspot.db ]; then # check if database file exists
    initDatabase
  else
    echo "Database already exists"
  fi
else
    if [ -n "$DB_ROOT_USER" ] || [ -n "$DB_ROOT_PW" ]; then
        echo "Please delete the environment variables \"DB_ROOT_USER\" and \"DB_ROOT_PW\" for security reasons and restart the container."
        exit 1
    fi
fi
