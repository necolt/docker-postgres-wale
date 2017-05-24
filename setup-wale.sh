#!/bin/bash

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
    echo "standby_mode     = 'on'" > $PGDATA/recovery.conf
    echo "restore_command  = 'envdir /etc/wal-e.d/env /usr/local/bin/wal-e wal-fetch "%f" "%p"'" >> $PGDATA/recovery.conf
    echo "trigger_file     = '$PGDATA/trigger'" >> $PGDATA/recovery.conf

    # Starting server again to satisfy init script
    pg_ctl -D "$PGDATA" -o "-c listen_addresses=''" -w start
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
