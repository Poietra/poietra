///|
pub(all) struct Position {
  id : String
  x : Double
  y : Double
}

///|
pub(all) struct Edge {
  from : String
  to : String
  directed : Bool
}

///|
pub(all) struct Degree {
  incoming : Int
  outgoing : Int
  undirected : Int
} derive(Eq, Debug)

///|
pub fn circle(ids : Array[String], radius : Double) -> Array[Position] {
  guard ids.length() <= 128 && !radius.is_nan() && !radius.is_inf() else {
    return []
  }
  let ids = ids.copy()
  ids.sort()
  Array::makei(ids.length(), fn(i) {
    let angle = 2.0 * @math.PI * i.to_double() / ids.length().to_double()
    { id: ids[i], x: radius * @math.cos(angle), y: radius * @math.sin(angle), }
  })
}

///|
pub fn degree(id : String, edges : Array[Edge]) -> Degree {
  let mut incoming = 0
  let mut outgoing = 0
  let mut undirected = 0
  for edge in edges {
    if edge.directed {
      if edge.from == id {
        outgoing += 1
      }
      if edge.to == id {
        incoming += 1
      }
    } else {
      if edge.from == id {
        undirected += 1
      }
      if edge.to == id {
        undirected += 1
      }
    }
  }
  { incoming, outgoing, undirected, }
}
