#!/bin/bash

if [ -n "$WALE_GPG_KEY_ID" ]
then
  gpg --keyserver keyserver.ubuntu.com --recv-keys $WALE_GPG_KEY_ID
  echo "$(gpg --list-keys --fingerprint | grep $WALE_GPG_KEY_ID -A 1 | tail -1 | tr -d '[:space:]' | cut -f2 -d'='):6:" | gpg --import-ownertrust
  gpg --import /private.key
fi

if [ "$POSTGRES_AUTHORITY" = "slave" ]
then
  echo "Authority: Slave - Fetching latest backups";

  if grep -q "/etc/wal-e.d/env" "/var/lib/postgresql/data/recovery.conf"; then
    echo "wal-e already configured in /var/lib/postgresql/data/recovery.conf"
  else
    sleep 5
    pg_ctl -D "$PGDATA" -w stop
    # $PGDATA cannot be removed so use temporary dir
    # If you don't stop the server first, you'll waste 5hrs debugging why your WALs aren't pulled
    envdir /etc/wal-e.d/env /usr/local/bin/wal-e backup-fetch /tmp/pg-data LATEST
    cp -rf /tmp/pg-data/* $PGDATA
    rm -rf /tmp/pg-data

    # Create recovery.conf
    echo "hot_standby      = 'on'" >> /var/lib/postgresql/data/postgresql.conf
    if [ -n "$POSTGRES_MAX_CONNECTIONS" ]; then
      echo "max_connections  = '$POSTGRES_MAX_CONNECTIONS'" >> /var/lib/postgresql/data/postgresql.conf
    fi
    echo "standby_mode     = 'on'" > $PGDATA/recovery.conf
    echo "restore_command  = 'envdir /etc/wal-e.d/env /usr/local/bin/wal-e wal-fetch "%f" "%p"'" >> $PGDATA/recovery.conf
    echo "trigger_file     = '$PGDATA/trigger'" >> $PGDATA/recovery.conf
    if [ -n "$POSTGRES_TIMESTAMP" ]; then
      echo "recovery_target_time = '$POSTGRES_TIMESTAMP'" >> $PGDATA/recovery.conf
    fi

    # Starting server again to satisfy init script
    pg_ctl -t 100000 -D "$PGDATA" -o "-c listen_addresses=''" -w start

    # Set password for 'postgres' user
    if [ -n "$POSTGRES_PASSWORD" ]; then
      psql -c "ALTER USER postgres PASSWORD '$POSTGRES_PASSWORD';"
    fi
  fi
else
  echo "Authority: Master - Scheduling WAL backups";

  if grep -q "/etc/wal-e.d/env" "/var/lib/postgresql/data/postgresql.conf"; then
    echo "wal-e already configured in /var/lib/postgresql/data/postgresql.conf"
  else
    echo "wal_level = archive" >> /var/lib/postgresql/data/postgresql.conf
    echo "archive_mode = on" >> /var/lib/postgresql/data/postgresql.conf
    echo "archive_command = 'envdir /etc/wal-e.d/env /usr/local/bin/wal-e wal-push %p'" >> /var/lib/postgresql/data/postgresql.conf
    echo "archive_timeout = 60" >> /var/lib/postgresql/data/postgresql.conf
  fi

  crontab -l | { cat; echo "0 3 * * * /usr/bin/envdir /etc/wal-e.d/env /usr/local/bin/wal-e backup-push /var/lib/postgresql/data"; } | crontab -
  crontab -l | { cat; echo "0 4 * * * /usr/bin/envdir /etc/wal-e.d/env /usr/local/bin/wal-e delete --confirm retain 30"; } | crontab -
fi
