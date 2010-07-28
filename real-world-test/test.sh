#!/bin/sh
set -x -e

db=haxe_db_tool_test_database

rm -fr generated-src
mkdir -p generated-src

run(){
  local type=$1
  args=" -cp ..  -main Test --php-front index.php --remap neko:php -php php "
  for step in 0 1 2 3; do
    # compile
    haxe $args -D step${step} -D prepare
    # create code
    php php/Test.php $type $step prepare
    # recomplie created code
    haxe $args -D step${step}
    # run compiled code
    php php/Test.php $type $step update

    php php/Test.php $type $step test
  done
}

  { # testing MySQL
  cat mysql-connection.txt | {
    read MYSQL_DATABASE
    read MYSQL_USER
    read MYSQL_PASSWORD
    read MYSQL_HOST
    read MYSQL_PORT
  }

  MYSQL="mysql -u $MYSQL_USER --password=$MYSQL_PASSWORD -h $MYSQL_HOST -P $MYSQL_PORT

  $MYSQL <<< "DROP DATABSE $MYSQL_DATABASE" || true
  $MYSQL <<< "CREATE DATABSE $MYSQL_DATABASE" || true

  run mysql

}

{ # testing Postgresql

  cat postgres-connection.txt | {
    read PGDATABASE
    read PGUSER ; export PGUSER
    read PGPASS ; export PGPASS
    read PGHOST ; export PGHOST
    read PGPORT ; export PGPORT
  }

  dropdb $PGDATABASE || true
  createdb $PGDATABASE

  run postgres
}
