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


using hxunit.Assert;

// project is too pre alpha

class Test_DBConnection extends TestCase {

  var con : DBConnection;

  override function setup(){
    this.con = new DBConnection(new Stub_Connection());
    super.setup();
  }


  function testAll(){

     // quoteName can't be tested
     assertEquals(con.substPH("?v", ["abc"]),"abc");
     assertEquals(con.substPH("?", ["abc"]),"\"abc\"");
     assertEquals(con.substPH("?w", [{a:"a",b:"b"}]),"( (a = \"a\") AND (b = \"b\") )");

  }

}
