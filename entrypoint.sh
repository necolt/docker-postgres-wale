#!/bin/bash

set -e

if [ "$1" = 'postgres' ]; then
  # Assumption: the group is trusted to read secret information
  umask u=rwx,g=rx,o=
  mkdir -p /etc/wal-e.d/env

  echo "$WALE_AWS_SECRET_ACCESS_KEY" > /etc/wal-e.d/env/AWS_SECRET_ACCESS_KEY
  echo "$WALE_AWS_ACCESS_KEY_ID" > /etc/wal-e.d/env/AWS_ACCESS_KEY_ID
  echo "$WALE_S3_PREFIX" > /etc/wal-e.d/env/WALE_S3_PREFIX
  echo "$WALE_AWS_REGION" > /etc/wal-e.d/env/AWS_REGION

  if [ -n "$WALE_GPG_KEY_ID" ]
  then
    echo "$WALE_GPG_KEY_ID" > /etc/wal-e.d/env/WALE_GPG_KEY_ID
    mkdir '/home/postgres'
    chown postgres:postgres /home/postgres
  fi

  chown -R root:postgres /etc/wal-e.d

  if [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo $PGDATA/PG_VERSION does not exist
  else
    echo $PGDATA/PG_VERSION exist, ensuring wal-e is set to run
    . ./docker-entrypoint-initdb.d/setup-wale.sh
  fi

  . ./docker-entrypoint.sh $1
fi

exec "$@"
