package db;

import db.DBTable;
import neko.db.Connection;

using StringTools;
using Lambda;
using Std;

/*
 

    var dbTool = new DBTool(cnx, {pathPrefix:"haxe/", fqn: ""}, "dbobjects");

    tables.addTable("User", [
        new DBField("oid", db_int),
        new DBField("firstname", db_varchar(50)),
        new DBField("lastname", db_varchar(50)),
        new DBField("last_login", db_date),
        new DBField("registered", db_date_auto(true, false)),
        new DBField("changed", db_date_auto(true, true)),
      ]);

    tables.addTable("UserSubscription",[
        new DBField("usr_oid", db_int).references("User","oid"),
        new DBField("subscriptionTYpe", db_haxe_enum_simple_as_index(SubscriptionType))
    ]);

    // this will create a class with a function scheme1(cnx:..){  /* create all tables or update them * / }
    // modify it so that it fits your needs. Eg adjust scheme updates etc.
    dbTool.prepareUpdate();
    dbTool.doUpdate();

*/


class DBTool {

  private var db_version_table:String;

  public var db_: neko.db.Connection;
  public var dbType: DBSupportedDatabaseType;
  public var data: {
    tables: Array<DBTable>
  };
  public var updateObjectFQN: { pathPrefix:String, fqn:String };
  public var packageName: String;

  public function addTable(name, fields){
    var t = new DBTable(name, fields);
    data.tables.push(t);
    return t;
  }

  public function new(
      conn: Connection,
      updateObjectFQN,
      packageName:String,
      ?tables: Array<DBTable>)
  {
    this.db_version_table = "db_version";
    this.db_ = conn;             // connection to operate on and to create queries for
    this.dbType = switch (this.db_.dbName()){
      case "PostgreSQL": db_postgres;
      case "Mysql": db_mysql;
    }
    this.updateObjectFQN = updateObjectFQN; // versioned .sql files are placed here. Before they are executed you can tweak them (allow running code?)
    this.data = {
      tables: tables // the object having functions scheme1() scheme2() .. running queries
    };
    if (tables == null)
      this.data.tables = new Array();
    addTable(db_version_table, [
        new DBField("version", db_int).uniq(),
        new DBField("hash_of_serialized_scheme", db_varchar(32))
      ]);
    this.packageName = packageName;
  }

  // implementation {{{1

  private function updateObjectData(fqn: { pathPrefix:String, fqn:String }){
    var ObjName = "DBUpdate"+db_.dbName();
    var prefix = fqn.pathPrefix+fqn.fqn.replace(".","/");

    return {
      path: prefix+"/"+ObjName+".hx",
      obj: ObjName
    }
  }


  function updateSPODS(up){
    info("updating SPODS not implemented yet ..");
  }

  function updateSchemeObject(up){

    var oldScheme: DBTool;

    if (!neko.FileSystem.exists(up.path)){
      var ini = 
          ( updateObjectFQN.fqn != "" ? " package "+updateObjectFQN.fqn : "")+"\n"
        + "class " + up.obj + " {\n"
        + "  static function request(db, sql){\n"
        + "    try {\n"
        + "       return db.request(sql);\n"
        + "    }catch(e:Dynamic){\n"
        + "      trace(\"error running sql:\\n\"+sql);\n"
        + "      throw e;\n"
        + "    }\n"
        + "  }\n"
        + "// scheme0:n\n"
        + "\n"
        + "}\n";
      info("writing initial file: "+up.path);
      var f =neko.io.File.write(up.path, true);
      f.writeString(ini);
      f.close();
    }
    info("reading "+up.path);
    var parsed = parseUpdateObject(up);

    var requests: Array<String> = new Array();
    if (parsed.dataOfLastScheme == null){
      parsed.dataOfLastScheme = { tables: new Array() };
    }
    var changeSets = DBHelper.sep(parsed.dataOfLastScheme.tables, data.tables);

    for (remove in changeSets.o)
      requests = requests.concat( DBTable.toSQL(dbType, remove, null));
    for (on in changeSets.k)
      requests = requests.concat( DBTable.toSQL(dbType, on.o, on.n) );
    for (new_ in changeSets.n){
      requests = requests.concat(DBTable.toSQL(dbType, null, new_));
    }
    if (requests.length == 0){
      info("nothing to be updated, returning");
      return;
    }

    var nextNr = parsed.version+1;

    var newFun = "  static public function scheme"+nextNr+"(db: neko.db.Connection){\n";

    if (parsed.version != 0){
      // verify that DB has scheme we're expecting:
      var expected = haxe.Md5.encode(parsed.dataUnserialized);
      newFun += "    var expectedHash = \""+expected+"\";\n";
      newFun += "    if ( expectedHash != db.request(\"SELECT hash_of_serialized_scheme FROM "+db_version_table+" WHERE version = "+parsed.version+"\").getResult(0)){\n";
      newFun += "      throw \"wrong branch ? refusing to update. Expected scheme hash :\"+expectedHash + \", version "+parsed.version+". Set this hash in the version table to continue\";\n";
    }
    var dataSerialized = haxe.Serializer.run(data);
    var thisHash = haxe.Md5.encode(dataSerialized);

    var reqAsString = function(req:String):String{
      var lines = new List();
        return "\""+req.replace("\"","\\\"")+"\"";
    }
    for (req in requests)
      newFun += "    request(db, \n"+reqAsString(req)+");\n";

    newFun += "    db.request(\"INSERT INTO "+db_version_table+" (version, hash_of_serialized_scheme) VALUES ("+nextNr+", \"+db.quote(\""+thisHash+"\")+\")\");\n";
    newFun += "  }\n";
    newFun += "// scheme"+nextNr+":"+dataSerialized;
    newFun += "\n";

    info("updating: "+up.path);
    var f =neko.io.File.write(up.path, true);
    var writeLines = function(list: Array<String>){ for (l in list) f.writeString(l+"\n"); }
    writeLines(parsed.before);
    f.writeString(newFun+"\n");
    writeLines(parsed.after);
    f.close();

  }

  // split Update file by last serialized scheme comment
  // return split file including last scheme version
  function parseUpdateObject(up){
    var lines = neko.io.File.getContent(up.path).split("\n").array();
    var before = new Array();
    var pending = new Array();

    for (l in lines){
      if (l.startsWith("// scheme")){
        pending.push(l);
        before = before.concat(pending);
        pending = [];
      } else pending.push(l);
    }

    var r = ~/^\/\/ scheme([0-9]+):(.*)/;
    var comment = before[before.length-1];
    r.match(comment);

    return {
      before: before,
      after: pending,
      version: Std.parseInt(r.matched(1)),
      dataOfLastScheme: haxe.Unserializer.run(r.matched(2)),
      dataUnserialized: r.matched(2)
    };

  }

  function check(){
    // check references
    var h = new Hash();
    var dup_names = new Hash();
    var dupFields = new Hash();
    data.tables.foreach(function(table){
        if (dup_names.exists(table.name))
          throw "table "+table.name+" was decalred twice!";
        dupFields.empty();
        table.fields.foreach(function(f){
            var n = table.name+"."+f.name;
            h.set(n, f.__uniq);
            if (dupFields.exists(f.name))
              throw "field "+n+" was decalred twice!";
            dupFields.set(f.name, true);
            return true;
        });
        dup_names.set(table.name, true);
        return true;
    });

    data.tables.foreach(function(table){
        table.fields.foreach(function(f){
          if (f.__references != null){
              var n = f.__references.table+"."+f.__references.field;
              if (!h.exists(n)) throw "a the field "+n+" is referenced by "+table.name+"."+f.name+" but doesn't exist";
              if (!h.get(n)) throw table.name+"."+f.name+" is referencing "+n+" which therefor must be uniq! (PG only .. still adviced)";
          };
          return true;
      });
      return true;
    });
  }

  // }}}

  // public interface {{{ 1
  // write files, create scheme Updates
  public function prepareUpdate(){
    check();
    var up = updateObjectData(updateObjectFQN);
    updateSchemeObject(up);
    updateSPODS(up);
  }

  // run scheme Updates
  public function doUpdate(){
    var up = updateObjectData(updateObjectFQN);
    var c = Type.resolveClass(up.obj);
    if (c==null){
      throw "trying to resolve class "+up.obj+" failed. Did you import it anywhere?";
    }

    // get latest scheme func nr:
    var max = 0;
    Type.getClassFields(c).foreach(function(name){
        if (name.startsWith("scheme")){
          var n = name.substr("scheme".length).parseInt();
          if (n > max) max = n;
        }
        return true;
    });

    // get latest scheme from db:
    var has_rows = 0 < db_.request("SELECT count(*) FROM "+db_version_table).getIntResult(0); // use LIMIT?
    var max_db =
      has_rows ? db_.request("SELECT max(version) FROM "+db_version_table).getIntResult(0);
      : 0;
    for (scheme in  (max_db+1 ... max+1)){
      info("updating to "+scheme);
      Reflect.callMethod(c, "scheme"+scheme, [db_]);
      info("done. scheme is "+scheme);
    }
  }

  function info(msg:Dynamic) {
    trace(msg);
  }
  // }}}

}
