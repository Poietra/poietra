///|
fn close(actual : Double, expected : Double) -> Unit raise {
  assert_true((actual - expected).abs() < 1.0e-8)
}

///|
test "numeric expressions retain mathematical precedence and editable parameters" {
  for
    (source, x, expected) in [
      ("x^3 - a*x", 2.0, 2.0),
      ("-x^2", 2.0, -4.0),
      ("2^3^2", 0.0, 512.0),
      ("2^-2", 0.0, 0.25),
      ("3x + 2(x+1)", 2.0, 12.0),
      ("a*x^2+b*x+c", 2.0, 25.0),
      ("sin(pi/2) + cos(0) + ln(e)", 0.0, 3.0),
      ("min(2, max(3, 4)) + pow(3, 2)", 0.0, 11.0),
      ("sqrt(abs(-9)) + floor(2.9) + ceil(2.1)", 0.0, 8.0),
      ("1e-2*x + 2e", 100.0, 1.0 + 2.0 * 2.718281828459045),
      ("  x  + a ", 2.0, 5.0),
    ] {
    close(prepare(source).evaluate(x, 3.0, 4.0, 5.0).unwrap(), expected)
  }
  let cubic = prepare("x^3-a*x")
  close(cubic.evaluate(2.0, 1.0, 0.0, 0.0).unwrap(), 6.0)
  close(cubic.evaluate(-2.0, 3.0, 0.0, 0.0).unwrap(), -2.0)
}

///|
test "undefined and overflowing expressions never become finite through outer operations" {
  for
    source in [
      "1/x", "sqrt(-1)", "ln(0)", "exp(1000)", "min(exp(1000), 1)", "atan(exp(1000))",
      "max(sqrt(-1), 1)",
    ] {
    assert_true(prepare(source).evaluate(0.0, 0.0, 0.0, 0.0) is None)
  }
}

///|
test "unrecognized syntax and recursive input are rejected with bounded work" {
  let nested = StringBuilder()
  for _ in 0..<150 {
    nested.write_string("(")
  }
  nested.write_string("x")
  for _ in 0..<150 {
    nested.write_string(")")
  }
  let long = StringBuilder()
  for _ in 0..<513 {
    long.write_string("x")
  }
  for
    source in [
      "",
      "x +",
      "sin x",
      "sin(x, 1)",
      "min(x)",
      "y",
      "window.alert(1)",
      "x;1",
      "1.2.3",
      "1e999",
      nested.to_string(),
      long.to_string(),
    ] {
    let rejected = try {
      prepare(source) |> ignore
      false
    } catch {
      InvalidExpression(_) => true
    }
    assert_true(rejected)
  }
}
