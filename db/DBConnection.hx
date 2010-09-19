package db;
import neko.db.Connection;

using Type;
using Lambda;

// same as neko.db.Connection. But adds more features

/* I'm awaret hat the implementation may not be the most efficient one
   However I think that my time is more valuable than some CPU cycles
*/

// should be overridden by backends for Postgresql etc
class DBConnection {

  public var cnx : neko.db.Connection;

  public var sqlLogger: String -> Void;

  public function new(cnx) {
    this.cnx = cnx;
  }

  // new stuff 


  // quotes both: table and field names
  public inline function quoteName(s:String):String{
    // default is not implemented .. Its unlikely that you use spaces. So this is for completeness
    return s;
  }

  // very simple form of placeholders {{{2

  // substitute placeholders
  //   ? : quoted value
  //   ?v: insert string verbatim (without quoting)
  //   ?n: quote name (table or field name)
  //   ?l: quote list for use in  WHERE field IN (a,b,c)
  //   ?w: {a:"abc", b:"foo"} yields a = "abc" AND b = "foo"
  //
  //   cnx.substPH("INSERT INSTO ?n VALUES (?,?,?v)", [ "table name", value1, value2.toString(), cnx.quote("a string")] )
  // note: the caller is responsible for converting a value into a string like
  //       thing which is understood by the database.
  public function substPH(query:String, args:Array<Dynamic>):String{
    if (args == null)
      return query;

    var parts = query.split("?");
    var s:StringBuf = new StringBuf();
    s.add(parts[0]);
    for( i in 1 ... parts.length ){
        var s_ = parts[i];
        var a:Dynamic = args[i-1];
        switch (s_.charAt(0)){
          case "n": // ?n
            s.add(this.quoteName(a));
            s.addSub(s_, 1, s_.length-1);
          case "v": // ?v
            s.add(a);
            s.addSub(s_, 1, s_.length-1);
          case "w": // ?w
            s.add(this.whereANDObj(a));
            s.addSub(s_, 1, s_.length-1);
          case "l": // ?l
            var first = true;
            s.add("(");
            var l:Array<Dynamic> = cast(a);
            for (x in l){
              if (!first)
                s.add(",");
              first = false;
              cnx.addValue(s, x);
            }
            s.add(")");
            s.addSub(s_, 1, s_.length-1);
          default: // ?
            cnx.addValue(s,a);
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
    var names = (fields == null ) ? Reflect.fields(o) : fields;

    var fields = new List();
    var values = new List();

    for( n in names ) {
      fields.add(this.quoteName(n));
      var f = Reflect.field(o,n);
      values.add((f==null) ? "NULL" : this.quote(f));
    }

    var s = new StringBuf();
    s.add("INSERT INTO ");
    s.add(this.quoteName(table));
    s.add(" (");
    s.add(fields.join(","));
    s.add(") VALUES (");
    s.add(values.join(","));
    s.add(")");

    return execute(s.toString());
  }

  public function insertMany(table:String, list:Array<Dynamic>, ?fields: Array<String>){
    if (list.length == 0) return;

    var names = (fields == null ) ? Reflect.fields(list[0]) : fields;

    var fields = new List();
    var rows = new List();

    var values = null;

    for( n in names ) {
      fields.add(this.quoteName(n));
    }

    for (obj in list){
      values = new List();
      for (n in names){
        values.add(this.quote(Reflect.field(obj,n)));
      }
      rows.push(values.join(","));
    }

    var s = new StringBuf();
    s.add("INSERT INTO ");
    s.add(this.quoteName(table));
    s.add(" (");
    s.add(fields.join(","));
    s.add(") VALUES (");
    s.add(rows.join("),("));
    s.add(")");

    execute(s.toString());
  }

  public function whereANDstr(l:Array<String>){
        return "( (" + l.join(") AND (" ) + ") )";
  }

  // generate the WHERE part of a query using AND
  // example usage:
  // cnx.substPH("UPDATE foo SET abc = ? WHERE ?w ", [ 10, {name : "abc"} ] )
  public function whereANDObj(?o:Dynamic, ?fields: Array<String>){

    if (o == null)
      return "1 == 1";

    var names = (fields == null ) ? Reflect.fields(o) : fields;

    switch (names.length){
      case 0:
        return "1 == 1";
      /*
      case 1:
        var n = names[0];
        return this.quoteName(n)+" = "+this.quote(Reflect.field(o, n));
        return "";
      */
      default:
        var l = new List();
        for (n in names){
          var v = Reflect.field(o,n);
          l.add( this.quoteName(n)
                + (v == null ? " IS NULL " : " = "+this.quote(v) )
              );
        }
        return whereANDstr(l.array());
    }
  }

  // cnx.delete("table",{id: "abc"});
  public function delete(table:String, o:Dynamic, ?fields: Array<String>){
    execute("DELETE FROM "+this.quoteName(table)+" WHERE "+this.whereANDObj(o, fields) );
  }

  // example usage: cnx.update("users", {name: "A.B"}, null, {id: 10});
  public function update(table:String, values:Dynamic, ?valueFields: Array<String>, where:Dynamic, whereFields:Array<String>){
    var valueNames = (valueFields == null) ? Reflect.fields(values) : valueFields;

    var sets = new List();

    for( n in valueNames ) {
      sets.add(this.quoteName(n)+"="+Reflect.field(values,n));
    }

    return execute("UPDATE "+this.quoteName(table)+" WHERE "+this.whereANDObj(where, whereFields));
  }
  // 


  // this should be included in the compiler !
  static public function tryFinally<R>(body: Void -> R, finally_: Void -> Void):R{
    try {
      var r = body();
      finally_();
      return r;
    } catch(e:Dynamic){
      finally_();
      neko.Lib.rethrow(e);
    }
    return null;
  }

  // QUERY INTERAFCE {{{

  // force tidy up. a db query is that heavy compared to a function call - so
  // the lambda does no longer matter
  // close is not yet implemented

  // get result from db
  public function query<R>(s:String, withResult: DBResultSet -> R):R {
    var resultSet = new DBResultSet(request(s), this);

    return tryFinally(function(){
        return withResult(resultSet);
    }, function(){
      if (resultSet != null)
        resultSet.free();
    });
  }

  // return last insertId
  public function execute(s:String){
    request(s);
  }
  public function executePH(s:String, ?args:Array<Dynamic>){
    request(substPH(s, args));
  }

  public function queryIntColPH(s:String, ?args:Array<Dynamic>){
    return this.queryPH(s, args, function(r){ return r.getIntCol(); } );
  }
  public function queryStringColPH(s:String, ?args:Array<Dynamic>){
    return this.queryPH(s, args, function(r){ return r.getCol(); } );
  }

  public function queryIntPH(s:String, ?args:Array<Dynamic>){
    return this.queryPH(s, args, function(r){ return r.getIntResult(0); } );
  }

  public function queryStringPH(s:String, ?args:Array<Dynamic>){
    return this.queryPH(s, args, function(r){ return r.getResult(0); } );
  }

  public function queryResults(query_:String, ?args:Array<Dynamic>):List<Dynamic>{
    return this.queryPH(query_, args, function(r){ return r.results(); });
  }

  // run query quoted by susbtPH
  public function queryPH<R>(query_:String, args:Array<Dynamic>, withResult:DBResultSet -> R):R{
    return query(substPH(query_, args), withResult);
  }

  // don't provide request, force users to use query which call free {{
  private function request( s : String ){
    if (sqlLogger != null){
      sqlLogger(s);
    }
    return new DBResultSet(cnx.request(s), this);
  }

  // QUERY INTERAFCE END }}}

  // make neko.db.Connection stuff available

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
