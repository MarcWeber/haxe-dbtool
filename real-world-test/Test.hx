// see test.sh
import db.DBConnection;
import db.DBTool;
import db.DBTable;
import Types;

import utest.Runner;
import utest.ui.Report;
import utest.Assert;
import utest.TestResult;

import db.DBManager;

#if !prepare

  #if db_postgres
  import DBUpdatePostgreSQL;
  #elseif db_mysql
  import DBUpdateMySQL;
  #elseif db_sqlite
  import DBUpdateSQLite;
  #else
    TODO
  #end

  import dbobjects.SPODS;
#end

class Test {

  static public function dbTool(cnx): DBTool{
    var dbTool = new DBTool(cnx,
      {pathPrefix:"generated-src/", fqn: ""},
      {pathPrefix:"generated-src/", fqn:"dbobjects.SPODS"}
    ).addImports(["Types"]);

#if step1

    // its simple to declare a table:
    dbTool.addTable("Simple", ["id"], [
        new DBField("id", db_int).autoinc(),
        new DBField("man", db_bool).nullable(),
        new DBField("firstname", db_varchar(50)),
        new DBField("myenum", db_haxe_enum_simple_as_index("MyEnum")).indexed(),
        new DBField("birthday", db_datetime),
        // sqlite 3.* supports onInsert, but, but 2.7 does not
        new DBField("registered", db_datetime, cast([ new DBFDCurrentTimestmap() #if !db_sqlite .onUpdate() .onInsert() #end ]) ),
#if !db_mysql
        // see DBFDCurrentTimestmap
        new DBField("changed", db_datetime, cast([ new DBFDCurrentTimestmap() #if !db_sqlite .onUpdate() .onInsert() #end ]) ),
#end
      ]).className("SimpleAliased");
#end


    // start with dummy field,
    // in step 2 add primary key and all other fields. In step 3 remove them again
    // in step 3 remove fields again but man and firstname. change type (remove nullable, change length)
    dbTool.addTable("Simple2", 
        [
#if (step2)
        "id"
#end
        ],
        [
        new DBField("dummy", db_varchar(4)),

#if step2
        new DBField("id", db_int).autoinc(),

        new DBField("man", db_bool).nullable(),
        new DBField("firstname", db_varchar(50)),

        new DBField("myenum", db_haxe_enum_simple_as_index("MyEnum")).indexed(),
        new DBField("registered", db_datetime, cast([ new DBFDCurrentTimestmap().onUpdate() #if !db_sqlite .onInsert() #end ]) ),
#end

#if step3
        new DBField("man", db_bool), // no more .nullable
        new DBField("firstname", db_varchar(80)), // increase length
#end
    ]);

    return dbTool;
  }

  static function main() {
    var args = neko.Sys.args();

    var database = args[0];
    var step = args[1];
    var task = args[2];

    var dbType: DBSupportedDatabaseType;
    var cnx: DBConnection;
    switch (database){
      case "mysql":
        dbType = db_mysql;
        var lines = neko.io.File.getContent("mysql-connection.txt").split("\n");
        cnx = new DBConnection(neko.db.Mysql.connect({
            host : lines[3],
            port : Std.parseInt(lines[4]),
            database : lines[0],
            user : lines[1],
            pass : lines[2],
            socket : null
        }));
      case "postgres":
        dbType = db_postgres;
        var lines = neko.io.File.getContent("postgres-connection.txt").split("\n");
        cnx = new DBConnection(neko.db.Postgresql.open("dbname="+lines[0]+" user="+lines[1]+" password="+lines[2]+" "
                      +(lines[3] == "" ? "" : "host="+lines[3]+" port="+lines[4]) ));
      case "sqlite":
        dbType = db_sqlite;
        var lines = neko.io.File.getContent("sqlite-connection.txt").split("\n");
        cnx = new DBConnection(neko.db.Sqlite.open(lines[0]));
      default:
        throw "unexpected first argument";
    }


    var dbt = dbTool(cnx.cnx);
    cnx.sqlLogger = function(s){ trace(s); };
    DBManager.cnx = cnx;

    switch (task){
      case "prepare":
        trace("preparing step"+step);
        dbt.prepareUpdate(dbType);
      case "update":
        trace("updating scheme step"+step);
        dbt.doUpdate();
      case "test":
        trace("running tests step "+step);
        trace("test that everything worked must be implemented - do you want to help me?");
        var runner = new Runner();
#if !prepare
#if step1

        runner.addCase(new TestStep1());
#elseif step2
        runner.addCase(new TestStep2());
#elseif step3
        runner.addCase(new TestStep3());
#elseif step4
        runner.addCase(new TestStep4());
#end
#end

        var r:TestResult = null;
        runner.onProgress.add(function(o){ if (o.done == o.totals) r = o.result;});
        Report.create(runner);
        runner.run();

        neko.Sys.exit(allOk(r) ? 0 : 1);
    }

  }


  static public function allOk(t :TestResult):Bool{
          for (l in t.assertations){
                  switch (l){
                          case Success(pos): break;
                          default: return false;
                  }
          }
          return true;
  }

}

#if !prepare
#if step1
class TestStep1 {

  public function new(){}

  function test() {
    var d = new Date(2010, 1, 20, 1,2,3);
    var u = new SimpleAliased("Marc", MyEnum.EA, d
      #if db_sqlite , Date.now() , Date.now() #end
    );

    try{
      // should throw Exception, because its too long
      Assert.equals(0,0);
      u.firstnameDB = "012345678 012345678 012345678 012345678 012345678 012345678";
      u.firstnameDB = "012345678 012345678 012345678 012345678 012345678 012345678";
      Assert.equals(1,0);

    }catch(e:Dynamic){
    }

    // test inserting object, that lastInsertId works, and that refetching object works {{{
    var ids = new Array();
    var num = 3;
    for (x in 0 ... num){
      ids.push(new SimpleAliased("firstname"+x, EA, d
            #if db_sqlite , Date.now() , Date.now() #end
            ).store().idDB
      );
    }
    // clear cache
    DBManager.cleanup();

    for (x in 0 ... num){
      var g = SimpleAliased.get(ids[x]);
      Assert.equals(g.firstnameDB, "firstname"+x);
      Assert.equals(g.myenumH, EA);
      var d = g.birthdayH;
      Assert.equals(d.getFullYear(), 2010);
      Assert.equals(d.getMonth(), 1);
      Assert.equals(d.getDate(), 20);
      Assert.equals(d.getHours(), 1);
      Assert.equals(d.getMinutes(), 2);
      Assert.equals(d.getSeconds(), 3);

      // insertion date should not be older than one minute
      trace(">>> "+g.registeredDB+" "+g.registeredH);
      Assert.isTrue(Date.now().getTime() - g.registeredH.getTime() < 60 * 1000 ); 
    }

  }

}
#elseif step2
class TestStep2 {

  public function new(){}

  public function test() {
     Assert.equals(0,0);
     // TODO
  }

}
#elseif step3
class TestStep3 {

  public function new(){}

  public function test() {
     Assert.equals(0,0);
     // TODO
  }

}
#elseif step4
class TestStep4 {

  public function new(){}

  public function test() {
     Assert.equals(0,0);
     // TODO
  }

}
#end
#end
