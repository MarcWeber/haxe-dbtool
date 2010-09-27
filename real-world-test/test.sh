#!/bin/bash

# HOWTO RUN THIS TEST
# ===================
# fill postgres-connection.txt mysql-connection.txt
# lines must fit values, see [1] and [2].
# Then bash test.sh or such.

# rewrite this test script in HaXe?

set -e

TESTS="postgres_test mysql_test sqlite_test"
BACKENDS="neko php"

die(){ echo "$@"; exit 1; }

for arg in "$@"; do
  case "$arg" in
    -d|--debug) set -x ;;
    mysql|postgres|sqlite)
      TESTS=
      TESTS="${arg}_test"
    ;;
    neko|php)
      BACKENDS="$arg"
    ;;
    --show-log)
      SHOW_LOG=1;
    ;;
    -h|--help)
      cat << EOF
      usage $0:
      -h or --help: print this usage
      postgres:  run Postgresql test only
      mysql:     run MySQL test only
      sqlite:    run Sqlite test only (experimental)

      php:  test php backend only
      neko: test neko backend only

      -d:        set -x
      --show-log
EOF
      die
    ;;
    *) 
      die "unexpected arg: $arg";
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
  echo "$@" | sed 's/ -/\n-/g' > current.hxml
  haxe "$@" || {
    echo "compilation failed"
    echo "compilation flags have been written to current.hxml"
    die
  }
}
 
RUN(){
  $RUN_BACKEND_CMD "$@" &> log.txt || {
    echo "backend exited nonzero ?"
    cat log.txt
    die
  }
  if grep \#1 log.txt &> /dev/null; then
    echo "exception running Test"
    cat log.txt
    die
  fi

  grep -e 'ERROR\|WARNING\|FAILURE' log.txt 2>&1 && {
    cat log.txt
    echo "log.txt contains ERROR, WARNING, FAILURE! aborting"
    die
  }

  [ -z "$SHOW_LOG" ] || cat log.txt
}

run(){
  local type=$1
  args="-lib utest -lib haxe-sql -cp .. -cp ../haxe-essentials $HAXE_BACKEND_FLAGS -cp generated-src "
  for step in 1 2 3; do
    echo
    INFO ">> $type step $step"

    INFO "compile so that prepare can be run"
    HAXE $args -D step${step} -D prepare -D db_$type
    INFO "preparing (generating code)"
    RUN $type $step prepare
    INFO "compile generated code"
    HAXE $args -D step${step} -D db_$type
    INFO "updating database (running gerenated code)"
    RUN $type $step update

    INFO "running tests on this scheme $step"
    RUN $type $step test
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

sqlite_test()
{
  rm sqlite.db || true
  run sqlite
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

for backend in $BACKENDS; do
  case "$backend" in
    php)
      HAXE_BACKEND_FLAGS="-main Test --php-front Test.php --remap neko:php -php php"
      RUN_BACKEND_CMD="php php/Test.php"
    ;;
    neko)
      HAXE_BACKEND_FLAGS="-debug -lib haxe-sql -main Test -neko Test.n"
      RUN_BACKEND_CMD="neko Test.n"
    ;;
    *)
      die "unkown backend"
    ;;
  esac
  for t in $TESTS; do
    $t
  done
done
