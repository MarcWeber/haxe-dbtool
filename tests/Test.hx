package tests;

class Test {
  
  static function main() {
    var runner = new hxunit.Runner();
    runner.addCase(new Test_DBConnection());
    runner.run();
  }    

}
