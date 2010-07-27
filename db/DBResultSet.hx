package db;


class DBResultSet implements neko.db.ResultSet{

  var set: php.db.ResultSet;

  public function new(resultSet: php.db.ResultSet) {
    this.set = resultSet;
  }

  public function getIntCol() {
    var l = new List();
    while(this.set.next() != null) {
      l.add(set.getIntResult(0));
    };
    return l;
  }
  public function getCol() {
    var l = new List();
    while(this.set.next() != null) l.add(this.set.getResult(0));
    return l;
  }
  public function getHash() {
    var h = new Hash();
    while(this.set.next() != null) h.set(this.set.getResult(0), this.set.next());
    return h;
  }

  // interface neko.db.ResultSet

  public var length(getLength,null) : Int;
  public var nfields(getNFields,null) : Int;
  public function getLength() {
    return set.length;
  }
  public function getNFields() {
    return set.length;
  }
  public function hasNext() {
    return set.hasNext();
  }
  public function next() : Dynamic {
    return set.next();
  }
  public function results() : List<Dynamic>{
    return set.results();
  }
  public function getResult( n : Int ) : String{
    return set.getResult(n);
  }
  public function getIntResult( n : Int ) : Int{
    return set.getIntResult(n);
  }
  public function getFloatResult( n : Int ) : Float{
    return set.getFloatResult(n);
  }
}
