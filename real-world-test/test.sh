#!/bin/bash

# HOWTO RUN THIS TEST
# ===================
# fill postgres-connection.txt mysql-connection.txt
# lines must fit values, see [1] and [2].
# Then bash test.sh or such.


set -e

TESTS="postgres_test mysql_test"

for arg in "$@"; do
  case "$arg" in
    -d|--debug) set -x ;;
    mysql|postgres) TESTS="${arg}_test"
    ;;
    -h|--help)
      cat << EOF
      usage $0:
      -h or --help: print this usage
      postgres:  run Postgresql test only
      mysql:     run MySQL test only
      -d:        set -x
EOF
      exit 1
    ;;
    *) 
      echo "unexpected arg: $arg";
      exit 1
    ;;
  esac
done

if [ "$1" == "-d" ]; then
  set -x
fi

db=haxe_db_tool_test_database

rm -fr generated-src php || true
mkdir -p generated-src

INFO(){ echo "INFO: $@"; }

INFO "starting tests"

HAXE(){
  # you have to split lines in current.hxml
  echo "$@" > current.hxml
  haxe "$@" || {
    echo "compilation failed"
    echo "compilation flags have been written to current.hxml"
    exit 1
  }
}
 
RUN(){
  local target=$1; shift

  case "$target" in
    php)
      php php/Test.php "$@" &> log.txt || {
        echo "php exited nonzero ?"
        cat log.txt
        exit 1
      }
      if grep \#1 log.txt &> /dev/null; then
        echo "exception running Test"
        cat log.txt
        exit 1
      fi
    ;;
    *)
    ;;
  esac
}

run(){
  local type=$1
  args=" -cp ..  -main Test --php-front Test.php --remap neko:php -php php -cp generated-src "
  for step in 1 2 3; do
    echo
    INFO ">> $type step $step"

    INFO "compile so that prepare can be run"
    HAXE $args -D step${step} -D prepare -D db_$type
    INFO "preparing (generating code)"
    RUN php $type $step prepare
    INFO "compile generated code"
    HAXE $args -D step${step} -D db_$type
    INFO "updating database (running gerenated code)"
    RUN php $type $step update

    INFO "running tests on this scheme $step"
    RUN php $type $step test
  done
}

mysql_test()
{
    INFO "testing MySQL"
    {
      # [1]
      read MYSQL_DATABASE
      read MYSQL_USER
      read MYSQL_PASSWORD
      read MYSQL_HOST
      read MYSQL_PORT
    } <<< "$(cat mysql-connection.txt)"

  MYSQL="mysql -u $MYSQL_USER --password=$MYSQL_PASSWORD -h $MYSQL_HOST -P $MYSQL_PORT"

  # recreate db
  $MYSQL <<< "DROP DATABASE $MYSQL_DATABASE" || true
  $MYSQL <<< "CREATE DATABASE $MYSQL_DATABASE"

  run mysql

}

postgres_test()
{
  INFO "testing Postgresql"

  {
    # [2]
    read PGDATABASE
    read PGUSER ; export PGUSER
    read PGPASS ; export PGPASS
    read PGHOST ; export PGHOST
    read PGPORT ; export PGPORT
  } <<< "$(cat postgres-connection.txt)"

  # recreate db
  dropdb $PGDATABASE || true
  createdb $PGDATABASE
  echo "CREATE LANGUAGE plpgsql" | psql $PGDATABASE

  run postgres
}

for t in $TESTS; do
  $t
done
