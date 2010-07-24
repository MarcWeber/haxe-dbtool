package db;
import neko.db.Connection;

using Type;
using Reflect;
using Lambda;

// same as neko.db.Connection. But adds more features

/* I'm awaret hat the implementation may not be the most efficient one
   However I think that my time is more valuable than some CPU cycles
*/

// should be overridden by backends for Postgresql etc
class DBConnection {

  public var cnx : neko.db.Connection;

  // new stuff {{{


  // quotes both: table and field names
  public inline function quoteName(s:String):String{
    // default is not implemented .. Its unlikely that you use spaces. So this is for completeness
    return s;
  }

  // very simple form of placeholders {{{2

  // run query quoted by susbtPH
  public function requestPH(cnx: Connection, query:String, args:Array<Dynamic>){
    return cnx.request(substPH(cnx, query, args));
  }

  // substitute placeholders
  //   ? : quoted value
  //   ?v: insert string verbatim (without quoting)
  //   ?n: quote name (table or field name)
  //
  //   cnx.substPH("INSERT INSTO ?n VALUES (?,?,?v)", [ "table name", value1, value2.toString(), cnx.quote("a string")] )
  // note: the caller is responsible for converting a value into a string like
  //       thing which is understood by the database.
  public function substPH(cnx: Connection, query:String, args:Array<Dynamic>){
    var parts = query.split("?");
    var s:StringBuf = new StringBuf();
    s.add(parts[0]);
    for( i in 1 ... parts.length ){
        var s_ = parts[i];
        var a = args[i-1];
        switch (s_.charAt(0)){
          case "n":
            s.add(this.quoteName(a));
            s.addSub(s_, 1, s_.length-1);
          case "v":
            s.add(a);
            s.addSub(s_, 1, s_.length-1);
          case "w":
          /* maybe this "w" case doesn't make much sense? */
            s.add(this.whereANDObj(a));
            s.addSub(s_, 1, s_.length-1);
          default:
            cnx.quote(a);
            s.add(s_);
        }
    }
    return s.toString();
  }
  // }}}2

  // example: cnx.insert("users", { name: "name", lastname: "lastname" });
  // you pass a list of names which should be included in the query
  // bascially this is what all the managers do for SPOD - but more generic
  // No need to have multiple implementations!
  public function insert(table:String, o:Dynamic, ?fields: Array<String>){
    var names = (fields == null ) ? o.intsanceFields() : fields;

    var fields = new List();
    var values = new List();

    for( n in names ) {
      fields.add(this.quoteName(n));
      values.add(o.field(n));
    }

    var s = new StringBuf();
    s.add("INSERT INTO ");
    s.add(this.quoteName(table));
    s.add(" (");
    s.add(fields.join(","));
    s.add(") VALUES (");
    s.add(values.join(","));
    s.add(")");

    return this.request(s.toString());
  }


  public function whereANDstr(l:Array<String>){
        return "( (" + l.join(" ) AND  (" ) + ") )";
  }

  // generate the WHERE part of a query using AND
  // example usage:
  // cnx.substPH("UPDATE foo SET abc = ? WHERE ?w ", [ 10, {name : "abc"} ] )
  public function whereANDObj(o:Dynamic, ?fields: Array<String>){

    var names = (fields == null ) ? o.intsanceFields() : fields;

    switch (names.length){
      case 0:
        return "1 == 1";
      case 1:
        var n = names[0];
        return this.quoteName(n)+" = "+o.field(n);
      default:
        var l = new List();
        for (n in names){
          l.add( this.quoteName(n)+" = "+o.field(n) );
        }
        return whereANDstr(l.array());
    }
  }

  // cnx.delete("table",{id: "abc"});
  public function delete(table:String, o:Dynamic, ?fields: Array<String>){
    this.request("DELETE FROM "+this.quoteName(table)+" WHERE "+this.whereANDObj(o, fields) );
  }

  // example usage: cnx.update("users", {name: "A.B"}, null, {id: 10});
  public function update(table:String, values:Dynamic, ?valueFields: Array<String>, where:Dynamic, whereFields:Array<String>){
    var valueNames = (valueFields == null) ? values.intsanceFields() : valueFields;

    var sets = new List();

    for( n in valueNames ) {
      sets.add(this.quoteName(n)+"="+values.field(n));
    }

    return this.request("UPDATE "+this.quoteName(table)+" WHERE "+this.whereANDObj(where, whereFields));
  }
  // }}}


  // make connection stuff available {{{
  public inline function request( s : String ){
    return cnx.request(s);
  }
  public inline function close(){
    cnx.close();
  }
  public inline function escape( s : String ){
    return cnx.escape(s);
  }
  public inline function quote( s : String ) : String {
    return cnx.quote(s);
  }
  public inline function addValue( s : StringBuf, v : Dynamic ) : Void {
    cnx.addValue(s,v);
  }
  public inline function lastInsertId() : Int{
    return cnx.lastInsertId();
  }
  public inline function dbName() : String {
    return cnx.dbName();
  }
  public inline function startTransaction() : Void{
    cnx.startTransaction();
  }
  public inline function commit() : Void {
    cnx.commit();
  }
  public inline function rollback() : Void{
    cnx.rollback();
  }
  // }}}

}
