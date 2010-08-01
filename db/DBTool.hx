package db;

import neko.db.Connection;
import db.DBTable;

using StringTools;
using Lambda;
using Std;

/*
 

    var dbTool = new DBTool(cnx, {pathPrefix:"haxe/", fqn: ""}, "dbobjects");

    // Postgres doesn't like a table named User, does it?
    tables.addTable("User_", [], [
        new DBField("oid", db_int),
        new DBField("firstname", db_varchar(50)),
        new DBField("lastname", db_varchar(50)),
        new DBField("last_login", db_date),
        new DBField("registered", db_date, cast([ new DBFDCurrentTimestmap().onUpdate().onInsert()])),
        new DBField("changed", db_date, cast([ new DBFDCurrentTimestmap().onUpdate().onInsert()])),
      ]).className("User");

    tables.addTable("UserSubscription", [], [
        new DBField("usr_oid", db_int).references("User","oid"),
        new DBField("subscriptionTYpe", db_haxe_enum_simple_as_index(SubscriptionType))
    ]);

    // dbTool.prepareUpdate(); create a class with a function

      public function scheme1(cnx:..){
        /* create all tables or update them * /
      }
    // modify it so that it fits your needs. Eg adjust scheme updates etc.
    // If that already exists the database scheme diff is written to scheme2(cnx:..)


    // this executes all schemeNR functions which have not been run on this
    // database yet:
    dbTool.doUpdate();

*/



class DBTool {

  private var db_version_table:String;

  public var db_: neko.db.Connection;
  public var dbType: DBSupportedDatabaseType;
  public var imports: Array<String>;
  public var data: {
    tables: Array<DBTable>
  };
  public var updateObjectFQN: { pathPrefix:String, fqn:String };
  public var spodPackage: {pathPrefix:String, pkg: String};

  public function addTable(name, primaryKeys, fields):DBTable{
    var t = new DBTable(name, primaryKeys, fields);
    data.tables.push(t);
    return t;
  }

  public function new(
      conn: Connection,
      updateObjectFQN,
      spodPackage,
      ?tables: Array<DBTable>)
  {
    this.db_version_table = "db_version";
    this.db_ = conn;             // connection to operate on and to create queries for
    var dbName = this.db_.dbName();
    this.dbType = switch (dbName){
      case "PostgreSQL": db_postgres;
      case "MySQL": db_mysql;
      default:
        throw "can't match "+dbName+" against neither: PostgreSQL, MySQL";
    }
    this.updateObjectFQN = updateObjectFQN; // versioned .sql files are placed here. Before they are executed you can tweak them (allow running code?)
    this.data = {
      tables: tables // the object having functions scheme1() scheme2() .. running queries
    };
    if (tables == null)
      this.data.tables = new Array();
    addTable(db_version_table, [], [
        new DBField("version", db_int).uniq(),
        new DBField("hash_of_serialized_scheme", db_varchar(32))
      ]);
    this.spodPackage = spodPackage;
    this.imports = [ "db.DBTable", "db.DBObject", "db.DBManager" ];
  }

  public function addImports(imports:Array<String>){
    this.imports = this.imports.concat(imports);
    return this;
  }

  // implementation {{{1

  function writeFile(path, lines:Array<String>){
    var f =neko.io.File.write(path, true);
    for (s in lines) f.writeString(s+"\n");
    f.close();
  }

  private function updateObjectData(fqn: { pathPrefix:String, fqn:String }){
    var ObjName = "DBUpdate"+db_.dbName();
    var prefix = fqn.pathPrefix+fqn.fqn.replace(".","/");

    return {
      path: prefix+"/"+ObjName+".hx",
      obj: ObjName
    }
  }

  static public var markers = {
    start : "  // GENERATED CODE START",
    end : "  // GENERATED CODE END",
    start_new : "  // GENERATED CODE START NEW",
    end_new : "  // GENERATED CODE END NEW"
  };

  function updateSPODS(db_:DBSupportedDatabaseType, up){
    for (t in data.tables){
     // trace("testing " + t.name);
      if (t.name == db_version_table || !t.__createSPODClass)
        continue;
      // keep it simple for now. Can be enhanced later
      var generatedCode = new Array();
      generatedCode.push(markers.start);

      var fieldsByName = new Hash();
      // add public vars
      for( f in t.fields ){
        var haxe = f.haxe(db_);
        fieldsByName.set(f.name, {field: f, haxe: haxe} );
        generatedCode.push(haxe.spodCode);
      }

      // primary keys
      if (t.primaryKeys.length > 0){
          generatedCode.push("  static var TABLE_IDS = ["+t.primaryKeys.map(function(s){ return "\""+s+"\""; }).join(", ")+"];");
          // retrieve object by key:
          // this is similar to manager.get(WithKeys). However its more type safe
          var args = new Array();
          var assignments = new Array();

          for( name in t.primaryKeys ){
            args.push(name+":"+fieldsByName.get(name).haxe.haxeType);
            assignments.push(name+" : "+name+"ToDB("+name+")");
          }
          // TODO optimize for one key, type Int
          generatedCode.push("  static inline public function get("+args.join(", ")+"):"+t.__SPODClassName+"{");
          generatedCode.push("    return manager.getWithKeys({"+assignments.join(", ")+"});");
          generatedCode.push("  }");

          generatedCode.push("  static inline public function getOrNew("+args.join(", ")+"):"+t.__SPODClassName+"{");
          generatedCode.push("    return manager.getOrNewWithKeys({"+assignments.join(", ")+"});");
          generatedCode.push("  }");
      }

      // table name
      if (t.name != t.__SPODClassName)
          generatedCode.push("  static var TABLE_NAME = \""+t.name+"\";");


      generatedCode.push(markers.end);

      var generatedCodeNew = new Array();
      var args_ = t.fields.map(function(f){
          var x =f.haxe(db_);
          return {
            name: f.name,
            newArg: x.newArg,
            haxe: x.haxeType
          }
        }).filter(function(f){ return f.newArg; });
      generatedCodeNew.push(markers.start_new);
      generatedCodeNew.push("  public function new("+ args_.map(function(f){return f.name+":"+f.haxe;}).join(", ") +"){");
      for (a in args_)
        generatedCodeNew.push("    this."+a.name+" = "+a.name+";");
      generatedCodeNew.push(markers.end_new);
      generatedCodeNew.push("");

      // TODO think about defaults and constructor

      var lines = new Array();
      // update or write file:
      var newText = "";
      var file = spodPackage.pathPrefix+"/"+spodPackage.pkg.replace(".","/")+"/"+t.__SPODClassName+".hx";

      var d = neko.io.Path.directory(file);
      if (!neko.FileSystem.exists(d)) neko.FileSystem.createDirectory(d);

      if (!neko.FileSystem.exists(file)){
        lines.push("package "+spodPackage.pkg+";");
        for (im in imports)
          lines.push("import "+im+";");
        lines.push("// import ..");

        lines.push("");
        lines.push("class "+t.__SPODClassName+" extends db.DBObject {");

        lines.push("  ");
        lines = lines.concat(generatedCodeNew);
        lines.push("  }");

        lines = lines.concat(generatedCode);
        lines.push("   public static var manager = new db.DBManager<"+t.__SPODClassName+">("+t.__SPODClassName+");");
        lines.push("}");


      } else {
        lines = neko.io.File.getContent(file).split("\n").array();

        // insert new() constructor
        var parsed = splitAtMarkers(lines, markers.start_new, markers.end_new);
        lines = parsed.before;
        lines = lines.concat(generatedCodeNew);
        lines = lines.concat(parsed.after);


        // insert fields
        parsed = splitAtMarkers(lines, markers.start, markers.end);
        lines = parsed.before;
        lines = lines.concat(generatedCode);
        lines = lines.concat(parsed.after);

      }

      info("writing (updating) SPOD class "+file);
      for (l in lines)
      writeFile(file, lines);

    }
  }

  static public function splitAtMarkers(lines:Array<String>, start, end){
    var buffer = new List();
    var before = new Array();
    var contents = new Array();
    for (l in lines)
      if (l == start){
        before = buffer.array();
      } else if (l == end) {
        buffer = new List();
      } else {
        buffer.add(l);
      }
    return { before: before, after: buffer.array() };
  }

  function updateSchemeObject(up){

    var oldScheme: DBTool;

    if (!neko.FileSystem.exists(up.path)){
      var inilines = new Array();
      inilines.push( updateObjectFQN.fqn != "" ? " package "+updateObjectFQN.fqn : "");
      inilines.push( "class " + up.obj + " {");
      inilines.push( "  static function request(db, sql){");
      inilines.push( "    try {");
      inilines.push( "       return db.request(sql);");
      inilines.push( "    }catch(e:Dynamic){");
      inilines.push( "      trace(\"error running sql:\\n\"+sql);");
      inilines.push( "      throw e;");
      inilines.push( "    }");
      inilines.push( "  }");
      inilines.push( "// scheme0:n");
      inilines.push( "");
      inilines.push( "}");
      info("writing initial file: "+up.path);
      writeFile(up.path, inilines);
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
      requests = requests.concat( DBTable.toSQL(dbType, null, new_));
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
      newFun += "    }\n";
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
    var tablesByName = new Hash();

    for (table in data.tables){

        tablesByName.set(table.name, table);

        if (dup_names.exists(table.name))
          throw "table "+table.name+" was declared twice!";

        var dupFields = new Hash();
        for (f in table.fields){
            var n = table.name+"."+f.name;
            h.set(n, f);
            if (dupFields.exists(f.name))
              throw "field "+n+" was declared twice!";
            dupFields.set(f.name, true);
        }

        dup_names.set(table.name, true);
    }

    for (table in data.tables){

        for (p in table.primaryKeys){
          var n = table.name+"."+p;
          if (!h.exists(n)) throw table.name+" has primary key item "+p+" which is not present in field list!";
        }

        for (f in table.fields){
          if (f.__references != null){
              var ref_tableName = f.__references.table;
              var ref_field = f.__references.field;
              var n = f.__references.table+"."+ref_field;
              if (!tablesByName.exists(ref_tableName))
                throw "referenced table "+ref_tableName+" does not exist!";
              var referenced_table = tablesByName.get(ref_tableName);
              if (!h.exists(n)) throw "a the field "+n+" is referenced by "+table.name+"."+f.name+" but doesn't exist";
              var referenced = h.get(n);
              var ref_pkeys = referenced_table.primaryKeys;
              if (!referenced.__uniq && !(ref_pkeys.length == 1 && ref_pkeys[0] == ref_field)) throw table.name+"."+f.name+" is referencing "+n+" which therefore must be uniq! (PG only .. still adviced)";
              if (f.type != referenced.type) throw table.name+"."+f.name+" is referencing "+n+"but field types differ";
          }
        }
    }
  }

  // }}}

  // public interface {{{ 1
  // write files, create scheme Updates
  public function prepareUpdate(db){
    check();
    var up = updateObjectData(updateObjectFQN);
    updateSchemeObject(up);
    updateSPODS(db, up);
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
    var max_db = 0;
    try {
      var has_rows = 0 < db_.request("SELECT count(*) FROM "+db_version_table).getIntResult(0); // use LIMIT?
      max_db =
        has_rows ? db_.request("SELECT max(version) FROM "+db_version_table).getIntResult(0)
        : 0;
    }catch(e:Dynamic){
      info("it seems this is an initial database ? Couldn't get version info from "+db_version_table);
    }
    if (max_db == max){
      info("db is up to date");
    } else {
      for (scheme in (max_db+1 ... max+1)){
        info("updating to "+scheme);
        Reflect.callMethod(c, "scheme"+scheme, [db_]);
        info("done. scheme is "+scheme);
      }
    }
  }

  function info(msg:Dynamic) {
    //trace(msg);
  }
  // }}}

}
