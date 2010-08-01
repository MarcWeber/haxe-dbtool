// see test.sh
import db.DBConnection;
import db.DBTool;
import db.DBTable;
import Types;

import utest.Runner;
import utest.ui.Report;
import utest.Assert;
import utest.TestResult;

#if !prepare
#if db_postgres
import DBUpdatePostgreSQL;
#elseif db_mysql
import DBUpdateMySQL;
#else
  TODO
#end

#if step1
  import dbobjects.SimpleAliased;
#end
  import dbobjects.Simple2;
#end

class Test {

  static public function dbTool(cnx): DBTool{
    var dbTool = new DBTool(cnx,
      {pathPrefix:"generated-src/", fqn: ""},
      {pathPrefix:"generated-src/", pkg:"dbobjects"}
    ).addImports(["Types"]);

#if step1

    // its simple to declare a table:
    dbTool.addTable("Simple", ["id"], [
        new DBField("id", db_int).autoinc(),
        new DBField("man", db_bool).nullable(),
        new DBField("firstname", db_varchar(50)),
        new DBField("myenum", db_haxe_enum_simple_as_index("MyEnum")).indexed(),
        new DBField("registered", db_date, cast([ new DBFDCurrentTimestmap().onUpdate().onInsert()]) ),
#if !db_mysql
        // see DBFDCurrentTimestmap
        new DBField("changed", db_date, cast([ new DBFDCurrentTimestmap().onUpdate().onInsert()]) ),
#end
      ]).className("SimpleAliased");
#end


    // start with dummy field,
    // in step 2 add primary key and all other fields. In step 3 remove them again
    // in step 3 remove fields again but man and firstname. change type (remove nullable, change length)
    dbTool.addTable("Simple2", 
        [
#if step2
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
        new DBField("registered", db_date, cast([ new DBFDCurrentTimestmap().onUpdate().onInsert()]) ),
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
        cnx = new DBConnection(php.db.Postgresql.open("dbname="+lines[0]+" user="+lines[1]+" password="+lines[2]+" "
                      +(lines[3] == "" ? "" : "host="+lines[3]+" port="+lines[4]) ));
      default:
        throw "unexpected first argument";
    }


    var dbt = dbTool(cnx.cnx);

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
    var u = new SimpleAliased("Marc", MyEnum.EA);
    try{
      // should throw Exception, because its too long
      Assert.equals(0,0);
      u.firstname = "012345678 012345678 012345678 012345678 012345678 012345678";
      Assert.equals(1,0);
    }catch(e:Dynamic){
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
