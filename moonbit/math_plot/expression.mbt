///|
pub(all) suberror InvalidExpression {
  InvalidExpression(String)
} derive(Debug)

///|
priv enum Variable {
  X
  Y
  A
  B
  C
}

///|
priv enum Unary {
  Negate
  Sin
  Cos
  Tan
  Asin
  Acos
  Atan
  Exp
  Log
  Sqrt
  Abs
  Floor
  Ceil
}

///|
priv enum Binary {
  Add
  Subtract
  Multiply
  Divide
  Power
  Minimum
  Maximum
}

///|
priv enum Expression {
  Number(Double)
  Input(Variable)
  Apply(Unary, Expression)
  Combine(Binary, Expression, Expression)
}

///|
/// Prepared, bounded numeric expressions have no host, clock or document access.
pub struct Program {
  priv expression : Expression
  priv implicit : Bool
}

///|
priv struct Parser {
  source : String
  allow_y : Bool
  allow_uv : Bool
  mut at : Int
  mut nodes : Int
}

///|
fn Parser::peek(self : Parser) -> Int {
  while self.at < self.source.length() &&
        [9, 10, 13, 32].contains(self.source.code_unit_at(self.at).to_int()) {
    self.at += 1
  }
  if self.at == self.source.length() {
    -1
  } else {
    self.source.code_unit_at(self.at).to_int()
  }
}

///|
fn Parser::take(self : Parser, unit : Int) -> Bool {
  if self.peek() == unit {
    self.at += 1
    true
  } else {
    false
  }
}

///|
fn Parser::raw(self : Parser) -> Int {
  if self.at < self.source.length() {
    self.source.code_unit_at(self.at).to_int()
  } else {
    -1
  }
}

///|
fn Parser::fail(
  self : Parser,
  message : String,
) -> Expression raise InvalidExpression {
  raise InvalidExpression(message + "（\{self.at + 1} 文字目）")
}

///|
fn Parser::node(
  self : Parser,
  expression : Expression,
) -> Expression raise InvalidExpression {
  self.nodes += 1
  if self.nodes > 128 {
    return self.fail("数式が複雑すぎます。")
  }
  expression
}

///|
fn identifier(unit : Int) -> Bool {
  (unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122)
}

///|
fn digit(unit : Int) -> Bool {
  unit >= 48 && unit <= 57
}

///|
fn Parser::primary(self : Parser) -> Expression raise InvalidExpression {
  let first = self.peek()
  if self.take(40) {
    // Count brackets too, bounding recursion even for deeply nested input.
    self.node(Number(0.0)) |> ignore
    let expression = self.sum()
    if !self.take(41) {
      return self.fail("閉じ括弧が必要です。")
    }
    return expression
  }
  if digit(first) || first == 46 {
    let start = self.at
    while digit(self.raw()) {
      self.at += 1
    }
    if self.raw() == 46 {
      self.at += 1
      while digit(self.raw()) {
        self.at += 1
      }
    }
    // Exponents require a digit after the optional sign; otherwise e is a constant.
    if self.at < self.source.length() &&
      [69, 101].contains(self.source.code_unit_at(self.at).to_int()) {
      let mut end = self.at + 1
      if end < self.source.length() &&
        [43, 45].contains(self.source.code_unit_at(end).to_int()) {
        end += 1
      }
      if end < self.source.length() &&
        digit(self.source.code_unit_at(end).to_int()) {
        self.at = end + 1
        while self.at < self.source.length() &&
              digit(self.source.code_unit_at(self.at).to_int()) {
          self.at += 1
        }
      }
    }
    let value = @string.parse_double(self.source[start:self.at]) catch {
      _ => return self.fail("数値を読み取れません。")
    }
    if value.is_nan() || value.is_inf() {
      return self.fail("有限な数値を指定してください。")
    }
    return self.node(Number(value))
  }
  if identifier(first) {
    let start = self.at
    while identifier(self.raw()) {
      self.at += 1
    }
    let name = self.source[start:self.at].to_owned()
    let variable = match name {
      "x" => Some(X)
      "y" if self.allow_y => Some(Y)
      "u" if self.allow_uv => Some(X)
      "v" if self.allow_uv => Some(Y)
      "a" => Some(A)
      "b" => Some(B)
      "c" => Some(C)
      _ => None
    }
    if variable is Some(input) {
      return self.node(Input(input))
    }
    if name == "pi" {
      return self.node(Number(@math.PI))
    }
    if name == "e" {
      return self.node(Number(2.718281828459045))
    }
    let unary = match name {
      "sin" => Some(Sin)
      "cos" => Some(Cos)
      "tan" => Some(Tan)
      "asin" => Some(Asin)
      "acos" => Some(Acos)
      "atan" => Some(Atan)
      "exp" => Some(Exp)
      "ln" | "log" => Some(Log)
      "sqrt" => Some(Sqrt)
      "abs" => Some(Abs)
      "floor" => Some(Floor)
      "ceil" => Some(Ceil)
      _ => None
    }
    if unary is None && !["min", "max", "pow"].contains(name) {
      return self.fail(
        "使える変数は " +
        (if self.allow_y { "x・y・a・b・c" } else { "x・a・b・c" }) +
        " です。関数名を確認してください。",
      )
    }
    self.node(Number(0.0)) |> ignore
    if !self.take(40) {
      return self.fail("関数には括弧を付けてください。")
    }
    let a = self.sum()
    if unary is Some(operation) {
      if !self.take(41) {
        return self.fail("閉じ括弧が必要です。")
      }
      return self.node(Apply(operation, a))
    }
    if !self.take(44) {
      return self.fail(
        "二つの引数をカンマで区切ってください。",
      )
    }
    let b = self.sum()
    if !self.take(41) {
      return self.fail("閉じ括弧が必要です。")
    }
    return self.node(
      Combine(
        match name {
          "min" => Minimum
          "max" => Maximum
          _ => Power
        },
        a,
        b,
      ),
    )
  }
  self.fail("数値・変数・括弧を指定してください。")
}

///|
fn Parser::power(self : Parser) -> Expression raise InvalidExpression {
  let a = self.primary()
  if self.take(94) {
    self.node(Number(0.0)) |> ignore
    self.node(Combine(Power, a, self.unary()))
  } else {
    a
  }
}

///|
fn Parser::unary(self : Parser) -> Expression raise InvalidExpression {
  if self.take(43) {
    self.node(Number(0.0)) |> ignore
    self.unary()
  } else if self.take(45) {
    self.node(Number(0.0)) |> ignore
    self.node(Apply(Negate, self.unary()))
  } else {
    self.power()
  }
}

///|
fn Parser::product(self : Parser) -> Expression raise InvalidExpression {
  let mut a = self.unary()
  while true {
    let next = self.peek()
    let operation = if self.take(42) {
      Some(Multiply)
    } else if self.take(47) {
      Some(Divide)
    } else if next == 40 || identifier(next) {
      Some(Multiply)
    } else {
      None
    }
    guard operation is Some(operation) else { break }
    a = self.node(Combine(operation, a, self.unary()))
  }
  a
}

///|
fn Parser::sum(self : Parser) -> Expression raise InvalidExpression {
  let mut a = self.product()
  while true {
    let operation = if self.take(43) {
      Some(Add)
    } else if self.take(45) {
      Some(Subtract)
    } else {
      None
    }
    guard operation is Some(operation) else { break }
    a = self.node(Combine(operation, a, self.product()))
  }
  a
}

///|
fn parse(
  source : String,
  implicit : Bool,
  surface? : Bool = false,
) -> Program raise InvalidExpression {
  if source.is_empty() || source.length() > 512 {
    raise InvalidExpression(
      "数式は 1〜512 文字で指定してください。",
    )
  }
  let parser : Parser = {
    source,
    allow_y: implicit || surface,
    allow_uv: surface,
    at: 0,
    nodes: 0,
  }
  let left = parser.sum()
  let expression = if implicit {
    if !parser.take(61) {
      parser.fail(
        "陰関数は x^2+y^2=1 のような等式で指定してください。",
      )
      |> ignore
    }
    parser.node(Combine(Subtract, left, parser.sum()))
  } else {
    left
  }
  if parser.peek() != -1 {
    parser.fail("数式の末尾を読み取れません。") |> ignore
  }
  { expression, implicit, }
}

///|
pub fn prepare(source : String) -> Program raise InvalidExpression {
  parse(source, false)
}

///|
/// Two independent coordinates, with u/v aliases confined to surface syntax.
pub fn prepare_surface(source : String) -> Program raise InvalidExpression {
  parse(source, false, surface=true)
}

///|
/// An equation is evaluated as its left side minus its right side.
pub fn prepare_implicit(source : String) -> Program raise InvalidExpression {
  parse(source, true)
}

///|
pub fn prepare_graph(
  source : String,
  syntax_version : Int,
) -> Program raise InvalidExpression {
  match syntax_version {
    1 => prepare(source)
    2 =>
      if source.contains("=") {
        prepare_implicit(source)
      } else {
        prepare(source)
      }
    _ =>
      raise InvalidExpression(
        "対応していない数式のバージョンです。",
      )
  }
}

///|
pub fn Program::is_implicit(self : Program) -> Bool {
  self.implicit
}

///|
fn evaluate(
  expression : Expression,
  x : Double,
  y : Double,
  a : Double,
  b : Double,
  c : Double,
) -> Double {
  match expression {
    Number(value) => value
    Input(variable) =>
      match variable {
        X => x
        Y => y
        A => a
        B => b
        C => c
      }
    Apply(operation, value) => {
      let value = evaluate(value, x, y, a, b, c)
      if value.is_nan() || value.is_inf() {
        return 0.0 / 0.0
      }
      match operation {
        Negate => -value
        Sin => @math.sin(value)
        Cos => @math.cos(value)
        Tan => @math.tan(value)
        Asin => @math.asin(value)
        Acos => @math.acos(value)
        Atan => @math.atan(value)
        Exp => @math.exp(value)
        Log => @math.ln(value)
        Sqrt => value.sqrt()
        Abs => value.abs()
        Floor => value.floor()
        Ceil => value.ceil()
      }
    }
    Combine(operation, left, right) => {
      let left = evaluate(left, x, y, a, b, c)
      let right = evaluate(right, x, y, a, b, c)
      if left.is_nan() || left.is_inf() || right.is_nan() || right.is_inf() {
        return 0.0 / 0.0
      }
      match operation {
        Add => left + right
        Subtract => left - right
        Multiply => left * right
        Divide => if right == 0.0 { 0.0 / 0.0 } else { left / right }
        Power => @math.pow(left, right)
        Minimum => left.min(right)
        Maximum => left.max(right)
      }
    }
  }
}

///|
pub fn Program::evaluate(
  self : Program,
  x : Double,
  a : Double,
  b : Double,
  c : Double,
) -> Double? {
  if self.implicit {
    return None
  }
  self.evaluate_at(x, 0.0, a, b, c)
}

///|
pub fn Program::evaluate_at(
  self : Program,
  x : Double,
  y : Double,
  a : Double,
  b : Double,
  c : Double,
) -> Double? {
  let value = evaluate(self.expression, x, y, a, b, c)
  if value.is_nan() || value.is_inf() {
    None
  } else {
    Some(value)
  }
}
