///|
fn Compiler::finish(self : Compiler) -> Plan raise CompileError {
  for tid, duration in self.durations {
    if !self.new_transitions.contains(tid) {
      self.emit(["transitions", tid, "duration"], ScalarValue(Number(duration)))
    }
  }
  for oid, _ in self.created {
    self.emit(["objects", oid], ObjectValue(self.objects[oid]))
    for cid in self.source.order {
      self.emit(
        ["compositions", cid, "states", oid],
        StateValue(self.state(cid, oid).unwrap()),
      )
    }
    for tid, transition in self.source.transitions {
      if !self.tracks.contains((tid, oid)) {
        self.emit(
          ["transitions", tid, "tracks", oid],
          TrackValue(
            {
              ..@scene.default_track(
                oid,
                self.durations.get(tid).unwrap_or(transition.duration),
              ),
              implicit: Some(true),
            },
            [],
          ),
        )
      }
    }
  }
  for _, entry in self.tracks {
    check_track(entry.value, entry.duration)
    if entry.existing && !entry.keyframe_ids.is_empty() {
      let original = (self.source.track)(entry.transition, entry.object_id)
        .bind(fn(t) { t.keyframes })
        .unwrap_or(Map([]))
      for id in entry.keyframe_ids {
        let next = entry.value.keyframes.unwrap()[id]
        let path = entry.path + ["keyframes", id]
        match original.get(id) {
          None => self.emit(path, KeyframeValue(next))
          Some(previous) => {
            if previous.at != next.at {
              self.emit(path + ["at"], ScalarValue(Number(next.at)))
            }
            if previous.property != next.property {
              self.emit(
                path + ["property"],
                ScalarValue(Text(@scene.curve_property_name(next.property))),
              )
            }
            if previous.value != next.value {
              self.emit(
                path + ["value"],
                ScalarValue(
                  match next.value {
                    CurveNumber(n) => Number(n)
                    CurveColor(s) => Text(s)
                  },
                ),
              )
            }
            if previous.easing != next.easing {
              self.emit(path + ["easing"], EasingValue(next.easing))
            }
            if previous.deleted != next.deleted {
              self.emit(
                path + ["deleted"],
                ScalarValue(Boolean(next.deleted == Some(true))),
              )
            }
          }
        }
      }
    }
    let transition = self.transitions[entry.transition]
    if entry.motion_edited && entry.value.path is Some(_) {
      if entry.value.type_ != Move {
        raise CompileError(
          "移動経路を使うアニメーションは Move にしてください。",
        )
      }
      for cid in [transition.from_id, transition.to_id] {
        if !(self.state(cid, entry.object_id) is Some({ visible: true, .. })) {
          raise CompileError(
            "移動経路には両方の Composition に表示されるオブジェクトが必要です。",
          )
        }
      }
    }
    if !self.new_transitions.contains(entry.transition) && !entry.existing {
      self.emit(entry.path, TrackValue(entry.value, entry.timing_fields))
    }
  }
  for cid in self.appended {
    let composition = self.compositions[cid]
    let incoming = self.new_transitions
      .iter()
      .find_first(fn(tid) { self.transitions[tid].to_id == cid })
      .unwrap()
    self.emit(
      ["compositions", cid],
      CompositionValue({
        id: cid,
        name: composition.name,
        duration: composition.duration,
        accent: composition.accent,
        states: self.all_states(cid),
        deleted: Some(false),
        incomingTransitionId: Some(incoming),
      }),
    )
  }
  for tid in self.new_transitions {
    let transition = self.transitions[tid]
    let tracks = Map([])
    let timings = Map([])
    for oid in self.objects.keys() {
      tracks[oid] = match self.tracks.get((tid, oid)) {
        Some(entry) => {
          timings[oid] = entry.timing_fields
          entry.value
        }
        None =>
          {
            ..@scene.default_track(oid, transition.duration),
            implicit: Some(true),
          }
      }
    }
    self.emit(
      ["transitions", tid],
      TransitionValue(
        {
          id: tid,
          fromId: transition.from_id,
          toId: transition.to_id,
          duration: transition.duration,
          tracks,
        },
        timings,
      ),
    )
  }
  { changes: self.changes, guards: self.guards, appended: self.appended, }
}

///|
pub fn compile(
  source : Source,
  operations : Array[Operation],
  allocate : (String) -> String,
) -> Plan raise CompileError {
  let compiler : Compiler = {
    source,
    objects: source.objects.copy(),
    compositions: source.compositions.copy(),
    transitions: source.transitions.copy(),
    order: source.order.copy(),
    states: Map([]),
    references: Map([]),
    declarations: Map([]),
    created: Map([]),
    appended: [],
    new_transitions: Set([]),
    durations: Map([]),
    tracks: Map([]),
    changes: [],
    guards: [],
  }
  compiler.prepare(operations, allocate)
  for index, operation in operations {
    compiler.execute(index, operation)
  }
  compiler.finish()
}
