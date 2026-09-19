///|
fn composition(
  id : String,
  name : String,
  duration : Double,
  accent : String,
) -> @scene.Composition {
  {
    id,
    name,
    duration,
    accent,
    states: Map([]),
    deleted: None,
    incomingTransitionId: None,
  }
}

///|
pub fn blank_scene(id : String, name : String) -> @scene.Scene {
  let cid = id + "-comp-1"
  {
    id,
    name,
    width: 1280.0,
    height: 720.0,
    background: "#08090b",
    objects: Map([]),
    audioTracks: Some(Map([])),
    compositionOrder: [cid],
    compositions: Map([
      (cid, composition(cid, "Composition 1", 1000.0, "#f4ce55")),
    ]),
    transitions: Map([]),
    deleted: None,
  }
}

///|
fn sample_object(
  id : String,
  name : String,
  kind : @scene.ObjectKind,
  order : Int,
  group : String?,
) -> @scene.SceneObject {
  {
    id,
    name,
    kind,
    order: order.to_double(),
    groupId: group,
    locked: false,
    image: None,
    media: None,
    playback: None,
  }
}

///|
pub fn demo_project() -> @scene.Project {
  let first = composition("comp-1", "Composition 1", 1000.0, "#f4ce55")
  let second = composition("comp-2", "Composition 2", 1600.0, "#14aab4")
  let objects = Map([])
  let add = fn(
    id : String,
    kind : @scene.ObjectKind,
    name : String,
    state : @scene.ObjectState,
    next : @scene.ObjectState,
  ) {
    objects[id] = sample_object(id, name, kind, objects.length(), None)
    first.states[id] = state
    second.states[id] = next
  }
  let path : @scene.ObjectState = {
    ..@scene.default_state(@scene.Path),
    x: 245.0,
    y: 520.0,
    width: 710.0,
    height: -330.0,
    strokeWidth: 2.0,
    path: { c1: { x: 260.0, y: 0.0, }, c2: { x: 420.0, y: -330.0, }, },
  }
  add("sigmoid", @scene.Path, "Sigmoid path", path, path)
  let circle : @scene.ObjectState = {
    ..@scene.default_state(@scene.Circle),
    x: 245.0,
    y: 520.0,
    width: 42.0,
    height: 42.0,
  }
  add("circle", @scene.Circle, "Circle", circle, {
    ..circle,
    x: 955.0,
    y: 190.0,
  })
  let equation : @scene.ObjectState = {
    ..@scene.default_state(@scene.Equation),
    x: 855.0,
    y: 440.0,
    width: 310.0,
    height: 70.0,
    fontSize: 50.0,
    visible: false,
  }
  add("equation", @scene.Equation, "Equation", equation, {
    ..equation,
    visible: true,
  })
  let transition : @scene.Transition = {
    id: "transition-1",
    fromId: first.id,
    toId: second.id,
    duration: 800.0,
    tracks: {
      "circle": {
        ..@scene.default_track("circle", 600.0),
        path: Some({ c1: { x: 505.0, y: 520.0, }, c2: { x: 665.0, y: 190.0, }, }),
      },
      "equation": {
        ..@scene.default_track("equation", 400.0),
        type_: @scene.Write,
        start: 400.0,
      },
    },
  }
  let scene : @scene.Scene = {
    ..blank_scene("scene-1", "Scene 1"),
    objects,
    compositionOrder: [first.id, second.id],
    compositions: Map([(first.id, first), (second.id, second)]),
    transitions: Map([(transition.id, transition)]),
  }
  {
    version: 1,
    name: "A little motion",
    sceneOrder: [scene.id],
    scenes: Map([(scene.id, scene)]),
  }
}
