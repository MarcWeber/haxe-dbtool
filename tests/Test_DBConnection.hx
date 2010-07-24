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


class Test_DBConnection extends TestCase {

  var con : DBConnection;

  public function new(){
    super();
    this.con = new DBConnection(new Stub_Connection());
  }

  function testAll(){
     // quoteName can't be tested
     assertEquals("abc", con.substPH("?v", ["abc"]));
     assertEquals("\"abc\"", con.substPH("?", ["abc"]));

     assertEquals("a = \"b\"", con.whereANDObj({a:"b"}));
     assertEquals("( (a = \"b\") AND (c = \"d\") )", con.whereANDObj({a:"b",c:"d"}));
     assertEquals("( (a = \"a\") AND (b = \"b\") )", con.substPH("?w", [{a:"a",b:"b"}]));

     assertEquals("(\"1\",\"2\",\"3\",\"4\")", con.substPH("?l", [[1,2,3,4]]));
  }

}
