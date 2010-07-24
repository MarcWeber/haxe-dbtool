package tests;

import neko.db.Mysql;

class Test {
  
  static function main() {
    var runner = new hxunit.Runner();
    runner.addCase(new Test_DBConnection());

    var p = neko.io.File.getContent("connection-mysql.txt").split("\n");
    var cnx = Mysql.connect({
      host : p[0],
      port : Std.parseInt(p[1]),
      user : p[2],
      pass : p[3],
      socket : null,
      database : p[5]
    });
    runner.addCase(new Test_LiveDB(cnx));

    runner.run();
  }    

}
