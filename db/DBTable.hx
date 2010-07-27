package db;

using Lambda;

// representing a database scheme

enum DBToolFieldType {
  db_varchar( length: Int );
  db_bool;
  db_int;
  db_enum( valid_items: List<String> );
  db_date;
  db_text; // text field. arbitrary length. Maybe no indexing and slow searching

  // store ints instead of the named Enum. Provide getter and setters for enum
  // values. Take care when remving or replacing enum values. You have to
  // adjust the inedxes then
  db_haxe_enum_simple_as_index(e:String);
}

enum DBToolFieldAutoValue {
  auto_inc;
}

enum DBEither<A,B> {
  db_left(x:A);
  db_right(x:B);
}

// supported databases
enum DBSupportedDatabaseType {
  db_mysql;
  db_postgres;
  // db_sqlite;
}

interface IDBSerializable {
  function toString():String;
}

class DBHelper {
  static public function concatArrays<T>(lists:List<Array<T>>): Array<T> {
    return lists.fold(function(a,b){return a.concat(b);}, []);
  }
  static public inline function assert(b:Bool, msg:String){ if (!b) throw msg; }
  static public function sep(o:Array<Dynamic>, n:Array<Dynamic>)
  :{o: List<Dynamic>, k: List<{o: Dynamic, n:Dynamic}>, n: List<Dynamic>}
    {
    var processed = new Hash();

    var old = new List();
    var keep = new List();
    var new_ = new List();

    var hash = new Hash();
    for (o_ in o) hash.set(o_.name, o_);

    for (n_ in n){
      if (hash.exists(n_.name)){
        keep.add( {o: hash.get(n_.name), n: n_} );
        hash.remove(n_.name);
      } else 
        new_.add(n_);
    }
    return { o: hash.list(), k: keep, n: new_};
  }
}

class DBFieldDecorator {

  public function decorate(db: DBSupportedDatabaseType, type: DBToolFieldType, tableName:String, field:String):{
    extraFieldText: String, // eg ON UPDATE CURRENT_TIMESTAMP or default CURRENT_TIMESTAMP
    sql_before: Array<String>,    // eg create postgresql sequence
    sql_after: Array<String>,     // eg setup trigger
    sql_remove: Array<String>,         // drop trigger and / or sequence
  } {
    throw "abstract method: DBFieldDecorator.decorate";
    return {
      extraFieldText: "",
      sql_before: [],
      sql_after: [],
      sql_remove: [],
    }
  }

  static public function merge(db_: DBSupportedDatabaseType, type: DBToolFieldType, tableName:String, field:String, decorators: Array<DBFieldDecorator>){
    var decorateList   = decorators.map(function(d){ return d.decorate(db_,  type, tableName, field); });
    return{
      extraFieldText  : decorateList.map(function(d){ return d.extraFieldText; }).join(" "),
      sql_before      : DBHelper.concatArrays(decorateList.map(function(d){ return d.sql_before; })),
      sql_after       : DBHelper.concatArrays(decorateList.map(function(d){ return d.sql_after; })),
      sql_remove      : DBHelper.concatArrays(decorateList.map(function(d){ return d.sql_remove; }))
    }
  }

}


class DBFDComment extends DBFieldDecorator {
  var __comment: String;

  public function new(comment:String) {
    __comment = comment;
  }

  override public function decorate(db_: DBSupportedDatabaseType, type: DBToolFieldType, tableName:String, field:String):{
    extraFieldText: String, // eg ON UPDATE CURRENT_TIMESTAMP or default CURRENT_TIMESTAMP
    sql_before: Array<String>,    // eg create postgresql sequence
    sql_after: Array<String>,     // eg setup trigger
    sql_remove: Array<String>,         // drop trigger and / or sequence
  } {
    // TODO quoting
    switch (db_){
      case db_postgres:
        return {
          extraFieldText : "COMMENT \""+__comment+"\"",
          sql_before : [],
          sql_after: [],
          sql_remove: []

        }
      case db_mysql:
        return {
          extraFieldText : "COMMENT \""+__comment+"\"",
          sql_before : [],
          sql_after: [],
          sql_remove: []
        }
    }
  }
}


class DBFDIndex extends DBFieldDecorator {
  var __uniq: Bool;

  public function new(?uniq:Bool) {
    __uniq = uniq;
  }

  override public function decorate(db_: DBSupportedDatabaseType, type: DBToolFieldType, tableName:String, field:String):{
    extraFieldText: String, // eg ON UPDATE CURRENT_TIMESTAMP or default CURRENT_TIMESTAMP
    sql_before: Array<String>,    // eg create postgresql sequence
    sql_after: Array<String>,     // eg setup trigger
    sql_remove: Array<String>,         // drop trigger and / or sequence
  } {
    var index_name = "index_"+tableName+"_"+field;
    switch (db_){
      case db_postgres:
        return {
          extraFieldText : "",
          sql_before : [],
          sql_after: ["CREATE "+(__uniq ? "UNIQ" : "" )+" INDEX "+index_name+" "+tableName+"("+field+")"],
          sql_remove: ["DROP INDEX "+index_name]

        }
      case db_mysql:
        return {
          extraFieldText : "",
          sql_before : [],
          sql_after: ["CREATE "+(__uniq ? "UNIQ" : "" )+" "+index_name+" INDEX "+tableName+"("+field+")"],
          sql_remove: ["DROP INDEX "+index_name]
        }
    }
  }
}

class DBFDCurrentTimestmap extends DBFieldDecorator {
  var __onInsert: Bool;
  var __onUpdate: Bool;

  public function new(){
  }

  public function onInsert(){
    __onInsert = true;
    return this;
  }

  public function onUpdate(){
    __onUpdate = true;
    return this;
  }

  override public function decorate(db_: DBSupportedDatabaseType, type: DBToolFieldType, tableName:String, field:String):{
    extraFieldText: String, // eg ON UPDATE CURRENT_TIMESTAMP or default CURRENT_TIMESTAMP
    sql_before: Array<String>,    // eg create postgresql sequence
    sql_after: Array<String>,     // eg setup trigger
    sql_remove: Array<String>,         // drop trigger and / or sequence
  } {
    if (type != db_date)
      throw "DBFDCurrentTimestmap only supports db_date fields!";

    switch (db_){
      case db_postgres:
        return {
          extraFieldText : __onInsert ? " default CURRENT_TIMESTAMP " : "",
          sql_before : [],
          sql_after: __onUpdate
                        ? ["
                          CREATE OR REPLACE FUNCTION update_timestamp_"+tableName+"_"+field+"() RETURNS TRIGGER 
                          LANGUAGE plpgsql
                          AS
                          $$
                          BEGIN
                              NEW."+field+" = CURRENT_TIMESTAMP;
                              RETURN NEW;
                          END;
                          $$;
                        ",
                        "
                          CREATE TRIGGER update_timestamp_"+tableName+"_"+field+"_trigger
                            BEFORE UPDATE
                            ON "+tableName+"
                            FOR EACH ROW
                            EXECUTE PROCEDURE update_timestamp_"+tableName+"_"+field+"();
                        "
                        ] : [],
          sql_remove:
            __onUpdate
            ? ["DROP TRIGGER update_timestamp_"+tableName+"_"+field+"_trigger",
               "DROP FUNCTION update_timestamp_"+tableName+"_"+field]
            : []

        }
      case db_mysql:
        return {
          extraFieldText : (__onInsert ? " default CURRENT_TIMESTAMP " : "")
                         + (__onUpdate ? " on update CURRENT_TIMESTAMP " : ""),
          sql_before : [],
          sql_after: [],
          sql_remove: []
        }
    }
      
  }

}


// represents a field
class DBField implements IDBSerializable {

  public var name: String;
  public var type: DBToolFieldType;
  public var __references: Null<{table: String, field: String}>;
  public var __autovalue: Null<DBToolFieldAutoValue>;
  public var __nullable: Bool;
  public var __uniq: Bool;
  public var __indexed: Bool;
  public var __default: Bool;
  public var __comment: String;
  public var __decorators: Array<DBFieldDecorator>;

  // serialization {{{2
  // create object from serialized string
  public function toString() {
    return haxe.Serializer.run(this);
  }
  
  static function unserialize(s:String):DBField{
    // be careful if you change the items
    // Here is the place to implement backward compatibility !!
    return haxe.Unserializer.run(s);
  }
  // }}}

  public function new(name: String, type:DBToolFieldType, ?decorators:Array<DBFieldDecorator>){
    this.name = name;
    this.type = type;
    __decorators = decorators == null ? [] : decorators;
    switch (type){
      case db_haxe_enum_simple_as_index(e):
        if (null == Type.resolveEnum(e))
          throw "invalid enum name "+e+" of field "+name;
      default:
    }
  }

  public function nullable(?nullable:Bool){
    __nullable = nullable != null && nullable;
  }

  public function autovalue(a: Null<DBToolFieldAutoValue>){
    this.__autovalue = a;
    return this;
  }

  public function references(table: String, field:String) {
    this.__references = { table : table, field : field };
    return this;
  }

  public function indexed() {
    this.__decorators.push(new DBFDIndex(false));
    return this;
  }

  public function uniq() {
    this.__decorators.push(new DBFDIndex(true));
    return this;
  }

  public function comment(c:String) {
    this.__comment = c;
    return this;
  }


  function field(name:String, haxeType:String){
     return
       "  private var _"+name+": "+haxeType+";\n"+
       "  public var "+name+"(get"+name+", set"+name+") : "+haxeType+";\n"+
       "  private function get"+name+"(): "+haxeType+" {\n"+
       "     return _"+name+";\n"+
       "  }\n"+
       "  private function set"+name+"(value : "+haxeType+"): "+haxeType+" {\n"+
       "    if (value == _"+name+") return _"+name+";\n"+
       "    this.__dirty_data = true;\n"+
       "    return _"+name+" = value;\n"+
       "  }\n";
  }

  // defines the DB <-> HaXe interface for this type
  public function haxe(db: DBSupportedDatabaseType):{
    // the db field type (TODO not yet used. Refactor!)
    dbType: String,

    // the HaXe type to be used
    haxeType: String,

    // the "public var field: Field;" line
    // may also contain additional getter/ setter code (eg enum type)
    // also contains NAMEtoHaxe NAMEToDB which converts HaXe <-> db types
    // this is inlined id func except enum types and such
    spodCode: String

    // TODO add DB setup and teardown hooks. eg autoincrement for Postgres
  }
  {


    switch (type){
      case db_varchar(length):
        return {
          dbType:  "varchar("+length+")",
          haxeType: "String",
          spodCode:
            field(name, "String")+
            "  static inline public function "+name+"ToHaXe(v: String):String { return v; }\n"+
            "  static inline public function "+name+"ToDB(v: String):String { return v; }\n"
        };
      case db_bool:
        return {
          dbType: "varchar(1)", // every db has varchar
          haxeType: "Bool",
          spodCode:
            field(name, "Bool")+
            "  static inline public function "+name+"ToHaXe(v: String):Bool { return (v == \"y\"); }\n"+ 
            "  static inline public function "+name+"ToDB(v: Bool):String { return v ? \"y\" : \"n\"; }\n"
        };
      case db_int:
        return {
          dbType: "Int",
          haxeType: "Int",
          spodCode:
            field(name, "Int")+
            "  static inline public function "+name+"ToHaXe(v: Int):Int { return v; }\n"+
            "  static inline public function "+name+"ToDB(v: Int):Int { return v; }\n"

        };
      case db_enum(valid_items):
        return {
          dbType: "String",
          haxeType: "String",
          spodCode:
            field(name, "String")+
            "  static inline public function "+name+"ToHaXe(v: String):String { return v; }\n"+
            "  static inline public function "+name+"ToDB(v: String):String { return v; }\n"
        };
      case db_date:
        // TODO
        return{ 
          dbType: "Date",
          haxeType: "Date",
          spodCode:
            field(name, "String")+
            "  static inline public function "+name+"ToHaXe(v: String):String { return v; }\n"+
            "  static inline public function "+name+"ToDB(v: String):String { return v; }\n"

        };
      case db_text:
        var dbType = switch (db){
          case db_postgres: "text";
          default: "text";
        }
        return {
          dbType: dbType,
          haxeType: "String",
          spodCode:
            field(name, "String")+
            "  static inline public function "+name+"ToHaXe(v: String):String { return v; }\n"+
            "  static inline public function "+name+"ToDB(v: String):String { return v; }\n"

        };
      case db_haxe_enum_simple_as_index(e):
        var gt = "get"+name+"AsEnum";
        var st = "set"+name+"AsEnum";
        var tE = name+"toEnum";
        return {
          dbType: "int",
          haxeType: e,
          spodCode:
            field(name, "Int")+
            "  static inline public function "+name+"ToHaXe(i:Int):"+e+"{ return Type.createEnumIndex("+e+", i); }\n"+
            "  static inline public function "+name+"ToDB(v: "+e+"):Int { return Type.enumIndex(v); }\n"+
            // getter + setter
            "   public var "+name+"AsEnum("+gt+", "+st+") : "+e+";\n"+
            "   function "+gt+"():"+e+"{ return  "+name+"ToHaXe("+name+"); }\n"+
            "   function "+st+"(value : "+e+") :"+e+"{ "+name+" = "+name+"ToDB(value); return value; }\n"
        };
    }


  }

  // returns message if type can't be represented in a dabatase
  // sql_before : ""; sql_after may be required to satisfy constraints or do more (?) not implemented yet. Maybe removed again
  static public function toSQL(
      db_: DBSupportedDatabaseType,
      tableName: String,
      old: Null<DBField>,
      new_:Null<DBField>,
      alter:Bool
    )
    :{ fields: Array<String>,
       fieldNames: Array<String>, // some fields are "virtual", they add multiple database fields. This is a list of all
       sql_before: Null<Array<String>>,
       sql_after: Null<Array<String>>
     }
  {

    switch (db_){

      // Postgres case {{{2
      case db_postgres:

        if (old == null){
          // create field

          var merged = DBFieldDecorator.merge(db_, new_.type, tableName, new_.name, new_.__decorators);

          var references = ( new_.__references == null ) ? "": " REFERENCES " + new_.__references.table + "("+ new_.__references.field + ")";
          var field:Array<String>;

          switch (new_.type){
            case db_varchar(length):
              field = [alter + new_.name+" varchar("+length+")" + merged.extraFieldText + references];
            case db_bool:
              field = [alter + new_.name+" bool" +  merged.extraFieldText + references];
            case db_int:
              field = [alter + new_.name+" int" +  merged.extraFieldText + references];
            case db_enum(valid_items):
              var f = function(x){ return "'"+x+"'"; };
              var enumTypeName = tableName+"_"+new_.name;
              return {
                fields: [alter + new_.name+" "+enumTypeName + " " +  merged.extraFieldText + references],
                fieldNames : [new_.name],
                sql_before : ["CREATE TYPE "+enumTypeName+ " AS ENUM ("+valid_items.map(f).join(",")+")"],
                sql_after : null
              }
            case db_date:
               field = [alter + new_.name+" timestamp " +  merged.extraFieldText + references];

            case db_text:
              field = [alter + new_.name+" text" +  merged.extraFieldText + references];

            case db_haxe_enum_simple_as_index(e):
              field = [alter + new_.name+" int" +  merged.extraFieldText + references];
          }

          return {
            fields: field,
            fieldNames: [ new_.name ],
            sql_before: merged.sql_before,
            sql_after : merged.sql_after,
          };

        } else if (new_ == null) {
          // drop field
          
          var merged = DBFieldDecorator.merge(db_, old.type, tableName, old.name, old.__decorators);
          var res = new Array();
          merged.sql_remove.push("ALTER TABLE "+tableName+" DROP FIELD "+old.name);

          // only cleanup enum field
          switch (old.type){
            case db_varchar(length):
            case db_bool:
            case db_int:
            case db_date:
            case db_text:
            case db_haxe_enum_simple_as_index(e):
            case db_enum(valid_items):
              var enumTypeName = tableName+"_"+old.name;
              var f = function(x){ return "'"+x+"'"; };
              merged.sql_after.push("DROP TYPE "+enumTypeName);
          }
          return {
            sql_after: merged.sql_remove,
            fields: [],
            fieldNames: [old.name],
            sql_before: null
          };
        } else {
          // change field
          if (old.name != new_.name)
            throw "not yet supported changing name of fields from "+old.name+" to "+new_.name;
          
          var old__create = DBField.toSQL(db_,tableName, null, old, false);
          var new__create = DBField.toSQL(db_,tableName, null, new_, false);

          var old__drop = DBField.toSQL(db_,tableName, old, null, false);
          var new__drop = DBField.toSQL(db_,tableName, new_, null, false);

          var setup_differ = (old__create.sql_after != new__create.sql_after)
                          || (old__create.sql_before != new__create.sql_before);

          var changeFields = new Array<String>();
          if (old__create.fields.length == new__create.fields.length){
            for (i in 0 ... old__create.fields.length){
              var n = old__create.fieldNames[i];
              changeFields.push("ALTER TABLE "+tableName+" CHANGE "+n+" "+n+" "+new__create.fields[i]);
            }
          } else {
            // drop old
            for (o in old__create.fields)
              changeFields.push("ALTER TABLE "+tableName+" DROP "+o);
            // create new
            for (n in new__create.fields)
              changeFields.push("ALTER TABLE "+tableName+" ADD "+n);
          }

          return {
            sql_before: (setup_differ ? new__create.sql_before : [])
                .concat(changeFields),
            sql_after: setup_differ ? old__drop.sql_after.concat(new__create.sql_after) : [],
            fields: [],
            fieldNames: []
          };
        }


      // MySQL case {{{2
      case db_mysql:

        if (old == null){
          // create field

          var merged = DBFieldDecorator.merge(db_, new_.type, tableName, new_.name, new_.__decorators);
          var nullable = (new_.__nullable) ? "" : " NOT NULL ";
          var references = ( new_.__references == null ) ? "": " REFERENCES " + new_.__references.table + "("+ new_.__references.field + ")";
          var field:Array<String>;
          switch (new_.type){
            case db_varchar(length):
              field = [new_.name+" varchar("+length+")" + nullable + merged.extraFieldText + references];
            case db_bool:
               field = [new_.name+" enum('y','n')"];
            case db_int:
              field = [new_.name+" int" + nullable + merged.extraFieldText + references];
            case db_enum(valid_items):
              var f = function(x){ return "'"+x+"'"; };
              return {
                fields: [new_.name+" enum("+ valid_items.map(f).join(",") +")" + nullable + merged.extraFieldText + references],
                fieldNames : [ new_.name ],
                sql_before : null,
                sql_after : null
              }

            case db_date:
              throw "TODO";
              // return { field: nalter + ew_.name+" time" + nullable + comment + references, sql_before : null, sql_after : null }

            case db_text:
              field = [alter + new_.name+" longtext" + nullable + merged.extraFieldText + references];
            case db_haxe_enum_simple_as_index(e):
              field = [alter + new_.name+" int" + nullable + merged.extraFieldText + references];
          }

          return {
            fields: field,
            fieldNames: [ new_.name ],
            sql_before : merged.sql_before,
            sql_after  : merged.sql_after,
          };
        } else if (new_ == null) {
          // drop field
          var merged = DBFieldDecorator.merge(db_, old.type, tableName, old.name, old.__decorators);
          var res = new Array();
          merged.sql_remove.push("ALTER TABLE "+tableName+" DROP FIELD "+old.name);

          // only cleanup enum field
          switch (old.type){
            case db_varchar(length):
            case db_bool:
            case db_int:
            case db_date:
            case db_text:
            case db_haxe_enum_simple_as_index(e):
            case db_enum(valid_items):
          }
          return {
            sql_after: merged.sql_remove,
            fields: [],
            fieldNames: [old.name],
            sql_before: null
          };


        } else {
          // change field
          if (old.name != new_.name)
            throw "not yet supported changing name of fields from "+old.name+" to "+new_.name;
          
          var old__create = DBField.toSQL(db_,tableName, null, old, false);
          var new__create = DBField.toSQL(db_,tableName, null, new_, false);

          var old__drop = DBField.toSQL(db_,tableName, old, null, false);
          var new__drop = DBField.toSQL(db_,tableName, new_, null, false);

          var setup_differ = (old__create.sql_after != new__create.sql_after)
                          || (old__create.sql_before != new__create.sql_before);

          var changeFields = new Array<String>();
          if (old__create.fields.length == new__create.fields.length){
            for (i in 0 ... old__create.fields.length){
              var n = old__create.fieldNames[i];
              changeFields.push("ALTER TABLE "+tableName+" CHANGE "+n+" "+n+" "+new__create.fields[i]);
            }
          } else {
            // drop old
            for (o in old__create.fields)
              changeFields.push("ALTER TABLE "+tableName+" DROP "+o);
            // create new
            for (n in new__create.fields)
              changeFields.push("ALTER TABLE "+tableName+" ADD "+n);
          }

          return {
            sql_before: (setup_differ ? new__create.sql_before : [])
                .concat(changeFields),
            sql_after: setup_differ ? old__drop.sql_after.concat(new__create.sql_after) : [],
            fields: [],
            fieldNames: []
          };
        }

    } // }}}
      
  }
  
}

// represents a table
class DBTable implements IDBSerializable {

  public var primaryKeys: Array<String>;
  public var name:String;
  public var fields: Array<DBField>;
  public var __SPODClassName: String; // name of generated class
  public var __createSPODClass: Bool; // if true SPOD class file will be created or updated

  // TODO extend by keys etc
  public function new(name, primaryKeys: Array<String>, fields) {
    this.fields = fields;
    this.name = name;
    this.primaryKeys = primaryKeys;
    this.__SPODClassName = name;
    this.__createSPODClass = true;
  }

  public function createSPODClass (b:Bool){
    this.__createSPODClass = b;
    return this;
  }

  public function className(n:String){
    this.__SPODClassName=n;
    return this;
  }

  // serialization {{{2
  // create object from serialized string
  public function toString() {
    return haxe.Serializer.run(this);
  }
  
  static function unserialize(s:String):DBField{
    // be careful if you change the items
    // Here is the place to implement backward compatibility !!
    return haxe.Unserializer.run(s);
  }
  // }}}
  
  // returns SQL queries which must be run to transform tabel old into table new
  static public function toSQL( db_: DBSupportedDatabaseType, old: Null<DBTable>, new_: Null<DBTable> ):Array<String> {
    var before = new List();
    var after = new List();
    var sqls = new List();

    var requests = new Array();
    var pushAll = function(r){
      if (r.sql_before != null)
        requests = requests.concat(r.sql_before);
      // requests = requests.concat(r.fields);
      if (r.sql_after != null)
        requests = requests.concat(r.sql_after);
    }

    switch (db_){

      // Postgres case {{{2
      case db_postgres:
        
        if (old == null) {
          // create table
            //trace("creating sql for table "+new_.name);

            var after = new Array();
            var before = new Array();

            var fields = new_.fields.map(function(f){
                var r = DBField.toSQL(db_, new_.name, null, f, false);
                if (r.sql_before != null)
                  before = before.concat(r.sql_before);
                if (r.sql_after != null)
                  after = after.concat(r.sql_after);
                return r.fields.join(",\n");
            }).join("\n,");

            requests = requests.concat(before);
            requests.push(
              "CREATE TABLE "+new_.name+ "(\n"
              + fields +"\n"
              + (new_.primaryKeys.length > 0 ? ", PRIMARY KEY ("+ new_.primaryKeys.join(", ")+") \n" : "" )
              +") WITH OIDS;\n");
            requests = requests.concat(after);

        } else if (new_ == null) {
          // drop table

          requests.push( "DROP TABLE "+old.name+ ";" );
          // possible cleanups (remove enum types ?)
          for (f in old.fields){
            var r = DBField.toSQL(db_, old.name, f, null, false);
            if (r.sql_after != null)
              requests = requests.concat(r.sql_after);
          }
            
        } else {
          // change table
          if (old.name != new_.name)
            throw "changing names not implemnted yet!";

          var changeSets = DBHelper.sep( old == null ? new Array() : old.fields
                        , new_ == null ? new Array() : new_.fields );

          for (n in changeSets.n){ pushAll(DBField.toSQL(db_, new_.name, null, n, true)); }
          for (k in changeSets.o){ pushAll(DBField.toSQL(db_, new_.name, k.o, k.n, true)); }
          for (o in changeSets.o){ pushAll(DBField.toSQL(db_, new_.name, o, null, true)); }

          if (old.primaryKeys != new_.primaryKeys){
            if (old.primaryKeys.length > 0)
              requests.push("ALTER TABLE "+old.name+" DROP CONSTRAINT "+old.name+"_pkey");

            if (new_.primaryKeys.length > 0)
              requests.push("ALTER TABLE "+new_.name+" ADD PRIMARY KEY ("+new_.primaryKeys.join(", ")+")");
          }

        }

      // MySQL case {{{2
      case db_mysql:

        if (old == null){
          // create table
          throw "MySQL TODO";


        } else if (new_ == null){
          // drop table
          requests.push( "DROP TABLE "+old.name+ ";" );
          throw "MySQL TODO";

        } else {
          // change table


          if (old.primaryKeys != new_.primaryKeys){
            if (old.primaryKeys.length > 0)
              requests.push("ALTER TABLE "+old.name+" DROP PRIMARY KEY");

            if (new_.primaryKeys.length > 0)
              requests.push("ALTER TABLE "+new_.name+" ADD PRIMARY KEY ("+new_.primaryKeys.join(", ")+")");
          }
          throw "MySQL TODO";
        }
    } // }}}

    return requests;
  }

}
