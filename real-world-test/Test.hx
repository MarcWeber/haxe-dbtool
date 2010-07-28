// see test.sh
import db.DBConnection;
import db.DBTool;
import db.DBTable;

#if !prepare
import DBUpdatePostgreSQL;

#if step1
  import dbobjects.Simple;
#end
  import dbobjects.Simple2;

#end

enum MyEnum {
  EA;
  EB;
}

class Test {

  static public function dbTool(cnx): DBTool{
    var dbTool = new DBTool(cnx,
      {pathPrefix:"generated-src/", fqn: ""},
      {pathPrefix:"generated-src/", pkg:"dbobjects"}
    );

#if step1

    // its simple to declare a table:
    dbTool.addTable("Simple", ["id"], [
        new DBField("id", db_int).autoinc(),
        new DBField("man", db_bool).nullable,
        new DBField("firstname", db_varchar(50)),
        new DBField("myenum", db_haxe_enum_simple_as_index("MyEnum")).indexed(),
        new DBField("registered", db_date, cast([ new DBFDCurrentTimestmap().onUpdate().onInsert()]) ),
        new DBField("changed", db_date, cast([ new DBFDCurrentTimestmap().onUpdate().onInsert()]) ),
      ]).className("User");
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
        new DBField("dummy", db_varchar(4))
#if step2
        new DBField("id", db_int).autoinc(),

        new DBField("man", db_bool).nullable,
        new DBField("firstname", db_varchar(50)),

        new DBField("myenum", db_haxe_enum_simple_as_index("MyEnum")).indexed(),
        new DBField("registered", db_date, cast([ new DBFDCurrentTimestmap().onUpdate().onInsert()]) ),
        new DBField("changed", db_date, cast([ new DBFDCurrentTimestmap().onUpdate().onInsert()]) ),
#end

#if step3

        new DBField("man", db_bool) // no more .nullable
        new DBField("firstname", db_varchar(80)), // increase length
#end
    ]);

    return dbTool;
  }

  static function main() {
    var args = neko.Sys.args();
    var dbType: DBSupportedDatabaseType;
    var cnx: DBConnection;
    switch (args[0]){
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
        cnx = new DBConnection(php.db.Postgresql.open("dbname="+lines[0]+" user="+lines[1]+" password="+lines[2]+" host="+lines[3]));
      default:
        throw "unexpected first argument";
    }

    var step = args[1];

    var dbt = dbTool(cnx.cnx);

    switch (args[2]){
      case "prepare":
        dbt.prepareUpdate(dbType);
      case "update":
        dbt.doUpdate();
      case "test":
        trace("test that everything worked must be implemented - do you want to help me?");
    }
  
  }

}
