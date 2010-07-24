package tests;
import neko.db.ResultSet;
// mock for neko.db.Connection
// only implement methods used by tests
class Stub_Connection implements neko.db.Connection {

  public function new() {
  }

  public function quote(s:String):String{
    return "\""+s+"\"";
  }


  public function addValue( s : StringBuf, v : Dynamic ) {
      s.add(quote(Std.string(v)));
  }

  public function close(){}
  public function startTransaction() {}
  public function commit(){}
  public function rollback(){}
  public function dbName(){return "stub";}
  public function escape( s : String ) {
          return untyped __call__("mysql_real_escape_string", s, c);
  }

  public function lastInsertId() {
    return -1;
  }

  public function request( s : String ) : ResultSet {
    return null;
  }
}
