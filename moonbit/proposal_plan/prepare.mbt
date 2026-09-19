///|
fn Compiler::prepare(
  self : Compiler,
  operations : Array[Operation],
  allocate : (String) -> String,
) -> Unit raise CompileError {
  self.depend(["deleted"])
  self.depend(["compositionOrder"])
  for id in self.source.raw_composition_ids {
    self.depend(["compositions", id, "deleted"])
    self.depend(["compositions", id, "incomingTransitionId"])
  }
  let mut append_count = 0
  let mut object_count = self.source.objects.length()
  for index, operation in operations {
    match operation {
      Create(creation) => {
        let state = creation.state
        for
          (field, value) in [
            (X, state.x),
            (Y, state.y),
            (Width, state.width),
            (Height, state.height),
          ] {
          validate_state(field, Number(value), Some(creation.kind))
        }
        if creation.kind != Image {
          validate_state(Fill, Text(state.fill), Some(creation.kind))
          validate_state(TextContent, Text(state.text), Some(creation.kind))
          validate_state(FontSize, Number(state.fontSize), Some(creation.kind))
        }
        object_count += 1
        if object_count > 500 {
          raise CompileError(
            "オブジェクトは 500 件まで追加できます。",
          )
        }
        self.declarations[index] = match creation.reference {
          Some(name) => self.reserve(name, ObjectRef, allocate)
          None => allocate("obj")
        }
      }
      Append(reference, transition, _, _, _) => {
        append_count += 1
        if append_count > 4 || self.source.order.length() + append_count > 100 {
          raise CompileError(
            "一度に追加できる Composition は 4 個まで、Scene 全体では 100 個までです。",
          )
        }
        self.reserve(reference, CompositionRef, allocate) |> ignore
        self.reserve(transition, TransitionRef, allocate) |> ignore
      }
      _ => ()
    }
  }
  let mut order = self.objects
    .values()
    .fold(init=-1.0, fn(order, object) { order.max(object.order) }) +
    1.0
  for index, operation in operations {
    match operation {
      TransitionDuration(reference, duration) => {
        let id = self.resolve(reference, TransitionRef)
        valid_duration(duration)
        self.durations[id] = duration
        if self.source.transitions.contains(id) {
          let transition = self.transition(id)
          for object_id in transition.track_ids {
            for
              key in [
                "objectId", "start", "duration", "implicit", "positionTiming", "opacityTiming",
                "sizeTiming", "rotationTiming", "fillTiming", "strokeTiming", "strokeWidthTiming",
                "fontSizeTiming", "cornerRadiusTiming", "pathTiming", "revealTiming",
              ] {
              self.depend(["transitions", id, "tracks", object_id, key])
            }
          }
        }
      }
      Create(creation) => {
        let id = self.declarations[index]
        let composition = self.resolve(creation.composition, CompositionRef)
        let name = @editor.trim_text(creation.name)
        let object : @scene.SceneObject = {
          id,
          name: if name.is_empty() {
            if creation.kind == Image {
              "Image"
            } else {
              @scene.object_kind_name(creation.kind)
            }
          } else {
            name[:name.length().min(100)].to_owned()
          },
          kind: creation.kind,
          order,
          locked: false,
          groupId: None,
          image: creation.image,
          media: None,
          playback: None,
        }
        order += 1.0
        self.created[id] = {
          object,
          state: creation.state,
          composition,
          declared: false,
        }
        self.objects[id] = object
        for cid in self.source.compositions.keys() {
          self.composition(cid) |> ignore
          self.set_state(cid, id, {
            ..creation.state,
            visible: cid == composition,
          })
        }
      }
      _ => ()
    }
  }
}
