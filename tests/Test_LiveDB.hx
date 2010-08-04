package tests;
import db.DBConnection;

import hxunit.Assert;
import hxunit.AssertionResult;
import hxunit.Runner;
import hxunit.TestCase;
import hxunit.TestContainer;
import hxunit.TestStatus;
import hxunit.TestSuite;
import hxunit.TestWrapper;

import hxunit.respond.CompositeResponder;
import hxunit.respond.Responder;


class Test_LiveDB extends TestCase {

  var con : DBConnection;

  public function new(mysql_cnx: neko.db.Connection){
    super();
    this.con = new DBConnection(mysql_cnx);
  }

  function testAll(){

    var t = "MY_USER_TABLE";

    // KISS: varchar, int should work for all dbs
    con.request("CREATE TABLE "+t+" (name varchar(200), lastname varchar(400), id int )");
    // try {

      var obj = {id: 1, name: "A", lastname: "B"};

      con.insert(t, obj);

      assertEquals("B", con.requestPH("SELECT * FROM ?n WHERE name = ?", [t, "A"]).next().lastname);

    // } finally {
      con.request("DROP TABLE "+t);
    // }
  }

}
