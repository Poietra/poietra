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

///|
test "two-variable equations evaluate their residual without changing explicit syntax" {
  for
    (source, x, y, expected) in [
      ("x^2+y^2=a^2", 3.0, 4.0, 16.0),
      ("y^2=x^3-x", 2.0, 3.0, 3.0),
      ("y=a*sin(x)+b", 0.0, 5.0, 1.0),
      ("x*y=0", 2.0, -3.0, -6.0),
      ("2(x+y)=c", 1.0, 2.0, 1.0),
    ] {
    let program = prepare_implicit(source)
    close(program.evaluate_at(x, y, 3.0, 4.0, 5.0).unwrap(), expected)
    assert_true(program.evaluate(x, 3.0, 4.0, 5.0) is None)
    close(
      prepare_graph(source, 2).evaluate_at(x, y, 3.0, 4.0, 5.0).unwrap(),
      expected,
    )
  }
  assert_true(
    prepare_implicit("1/x=y").evaluate_at(0.0, 2.0, 0.0, 0.0, 0.0) is None,
  )
  for
    source in [
      "x+y", "x==y", "x=y=1", "x<y", "x=", "=y", "x=(y=1)", "z=1", "x=globalThis.alert(1)",
    ] {
    let rejected = try {
      prepare_implicit(source) |> ignore
      false
    } catch {
      InvalidExpression(_) => true
    }
    assert_true(rejected)
  }
}

///|
test "surface u/v aliases remain unavailable to the existing 2D grammar" {
  close(
    prepare_surface("a*u+b*v+c").evaluate_at(2.0, 3.0, 4.0, 5.0, 6.0).unwrap(),
    29.0,
  )
  close(
    prepare_surface("x+y").evaluate_at(2.0, 3.0, 0.0, 0.0, 0.0).unwrap(),
    5.0,
  )
  for source in ["u", "v", "sin(u)", "u+v=1"] {
    assert_true(
      try {
        prepare(source) |> ignore
        false
      } catch {
        InvalidExpression(_) => true
      },
    )
    assert_true(
      try {
        prepare_implicit(source) |> ignore
        false
      } catch {
        InvalidExpression(_) => true
      },
    )
  }
  assert_true(
    try {
      prepare_surface("z=x+y") |> ignore
      false
    } catch {
      InvalidExpression(_) => true
    },
  )
}
