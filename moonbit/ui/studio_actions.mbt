///|
fn StudioController::select(
  self : StudioController,
  next : StudioSelection,
) -> Unit {
  self.stop()
  let doc = self.document
  let start = if truthy(doc.scene) {
    studio_segment_start(
      self.input._get("store")._call("scene", [@core.any(doc.scene_id)]),
      next.id(),
    )
  } else {
    0.0
  }
  self.update({
    ..self.state,
    selection: next,
    cursor: SelectedState,
    path_editing: false,
    playhead: start,
  })
}

///|
fn StudioController::change_scene(self : StudioController, id : String) -> Unit {
  self.stop()
  let next = self.input
    ._get("store")
    ._call("project", [])
    ._get("scenes")
    ._get(id)
  let selection = if truthy(next) {
    let order : FixedArray[String] = next._get("compositionOrder").cast()
    CompositionSelection(order[0])
  } else {
    self.state.selection
  }
  self.update({
    ..self.state,
    scene_id: id,
    selection,
    playhead: 0.0,
    cursor: SelectedState,
    objects: [],
    path_editing: false,
  })
}

///|
fn StudioController::new_scene(self : StudioController) -> Unit {
  attempt(
    fn() {
      self.change_scene(self.input._get("store")._call("addScene", []).cast())
    },
    fn(message) { self.notify(message) },
    "Scene を追加できませんでした。",
  )
}

///|
fn StudioController::append(self : StudioController) -> Unit {
  let doc = self.document
  if !truthy(doc.scene) {
    return
  }
  attempt(
    fn() {
      let store = self.input._get("store")
      let current = store._call("scene", [@core.any(doc.scene_id)])
      let order : FixedArray[String] = current._get("compositionOrder").cast()
      let previous = if order.is_empty() {
        @core.undefined()
      } else {
        current._get("compositions")._get(order[order.length() - 1])
      }
      let id : String = store
        ._call("addComposition", [@core.any(doc.scene_id)])
        .cast()
      self.select(CompositionSelection(id))
      let name : String = store
        ._call("scene", [@core.any(doc.scene_id)])
        ._get("compositions")
        ._get(id)
        ._get("name")
        .cast()
      let previous_name : String = if truthy(previous) {
        previous._get("name").cast()
      } else {
        "直前の場面"
      }
      self.notify(
        name +
        " を追加。" +
        previous_name +
        " の配置と内容を引き継ぎました。",
      )
    },
    fn(message) { self.notify(message) },
    "場面を追加できませんでした。",
  )
}

///|
fn StudioController::edit_moment(
  self : StudioController,
  composition_only : Bool,
) -> Unit {
  let doc = self.document
  if !truthy(doc.scene) || !truthy(doc.at_time) {
    return
  }
  let next = studio_selection(doc.at_time)
  let next = match next {
    TransitionSelection(id) if composition_only =>
      CompositionSelection(
        doc.scene._get("transitions")._get(id)._get("toId").cast(),
      )
    _ => next
  }
  let time = self.state.playhead
  self.select(next)
  if next is TransitionSelection(_) {
    let start : Double = doc.at_time._get("start").cast()
    let duration : Double = doc.at_time._get("duration").cast()
    self.update({
      ..self.state,
      playhead: @scene.clamp(time, start, start + duration),
    })
  }
}

///|
fn StudioController::activate(
  self : StudioController,
  tool : @editor.StageTool,
) -> Unit {
  self.stop()
  self.update({ ..self.state, tool, })
  if self.state.viewing() {
    self.edit_moment(!(tool is SelectTool))
  } else {
    self.update({ ..self.state, cursor: SelectedState, })
    if truthy(self.document.transition) {
      self.select(
        CompositionSelection(self.document.transition._get("toId").cast()),
      )
    }
  }
}

///|
fn StudioController::choose(
  self : StudioController,
  ids : Array[String],
) -> Unit {
  if self.state.viewing() {
    self.edit_moment(false)
  }
  self.update({ ..self.state, objects: ids, })
}

///|
fn StudioController::seek(
  self : StudioController,
  time : Double,
  scope : StudioScope,
) -> Unit {
  self.stop()
  self.update({
    ..self.state,
    path_editing: false,
    cursor: match scope {
      WholeScene => ScenePosition
      SelectedTransition => TransitionPosition
    },
    playhead: @scene.clamp(time, 0.0, self.document.total),
  })
}

///|
fn StudioController::play(self : StudioController, scope : StudioScope) -> Unit {
  if !(self.state.transport is Stopped) {
    self.stop()
    return
  }
  self.generation += 1
  let job = self.generation
  self.update({
    ..self.state,
    transport: Preparing(job, scope),
    audio_error: "",
  })
  @core.from_async(async fn() {
    try {
      ui_call(self.media, "unlock", []) |> ignore
      if !self.mounted ||
        self.generation != job ||
        !(self.state.transport is Preparing(id, _) && id == job) {
        return
      }
      let doc = self.document
      let begin = if scope == SelectedTransition && truthy(doc.selected) {
        doc.selected._get("start").cast()
      } else {
        0.0
      }
      let end = if scope == SelectedTransition {
        begin +
        (if truthy(doc.transition) {
          doc.transition._get("duration").cast()
        } else {
          0.0
        })
      } else {
        doc.total
      }
      let position = if self.state.playhead < begin ||
        self.state.playhead >= end - 1.0 {
        begin
      } else {
        self.state.playhead
      }
      self.clock = {
        time: @core.global_this()._get("performance")._call("now", []).cast(),
        position,
        end,
      }
      self.update({
        ..self.state,
        transport: Playing(scope),
        playhead: position,
        cursor: match scope {
          WholeScene => ScenePosition
          SelectedTransition => TransitionPosition
        },
      })
    } catch {
      error =>
        if self.mounted && self.generation == job {
          self.update({
            ..self.state,
            transport: Stopped,
            audio_error: error_message(
              ui_native_error(error),
              "音声を準備できませんでした。",
            ),
          })
        }
    }
  })
  |> ignore
}

///|
fn StudioController::text_edit(
  self : StudioController,
  object : String,
  composition : String,
) -> Unit {
  let doc = self.document
  if !truthy(doc.scene) {
    return
  }
  let current = self.input
    ._get("store")
    ._call("scene", [@core.any(doc.scene_id)])
  let item = current._get("objects")._get(object)
  let comp = current._get("compositions")._get(composition)
  if !truthy(item) || truthy(item._get("locked")) || !truthy(comp) {
    return
  }
  let kind : String = item._get("kind").cast()
  let state = comp._get("states")._get(object)
  if (kind != "text" && kind != "equation") ||
    !truthy(state) ||
    !truthy(state._get("visible")) {
    return
  }
  self.select(CompositionSelection(composition))
  self.update({
    ..self.state,
    objects: [object],
    tool: @editor.SelectTool,
    panel: DesignPanel,
    text_edit: Some({ scene: doc.scene_id, composition, object, }),
  })
}

///|
fn StudioController::undo(self : StudioController) -> Unit {
  attempt(
    fn() {
      let store = self.input._get("store")
      let retained : Int = store._call("undo", []).cast()
      let compositions : Int = store
        ._get("lastUndoPreservedCompositions")
        .cast()
      let objects : Int = store._get("lastUndoPreservedObjects").cast()
      let audio : Int = store._get("lastUndoPreservedAudioTracks").cast()
      let durations : Int = store._get("lastUndoPreservedDurations").cast()
      self.notify(
        if compositions > 0 {
          "共同編集者が使っている \{compositions} 個の新しい場面と、そのオブジェクト・動きを保持しました。"
        } else if objects > 0 {
          "共同編集者が変更した \{objects} 個の新規オブジェクトと、その状態・アニメーションを保持しました。"
        } else if audio > 0 {
          "共同編集者が変更した \{audio} 個の音声トラックを保持しました。"
        } else if retained > 0 {
          "共同編集者が変更した \{retained} 個の新規アニメーションを保持しました。"
        } else if durations > 0 {
          "共同編集者のアニメーションが収まるように、Transition の長さを保持しました。"
        } else {
          "元に戻しました"
        },
      )
    },
    fn(message) { self.notify(message) },
    "現在のアニメーションと競合するため、取り消せませんでした。",
  )
}

///|
fn StudioController::redo(self : StudioController) -> Unit {
  attempt(
    fn() {
      let retained : Int = self.input._get("store")._call("redo", []).cast()
      self.notify(
        if retained > 0 {
          "共同編集者のアニメーションが収まるように、Transition の長さを保持しました。"
        } else {
          "やり直しました"
        },
      )
    },
    fn(message) { self.notify(message) },
    "現在のアニメーションと競合するため、やり直せませんでした。",
  )
}

///|
fn StudioController::share(self : StudioController) -> Unit {
  @core.from_async(async fn() {
    try {
      let global = @core.global_this()
      ui_call(global._get("navigator")._get("clipboard"), "writeText", [
        global._get("location")._get("href"),
      ])
      |> ignore
      if !self.mounted {
        return
      }
      if self.copy_timer is Some(timer) {
        cancel_timer(timer)
      }
      self.update({ ..self.state, copied: true, })
      self.copy_timer = Some(
        schedule_timer(
          fn() {
            self.copy_timer = None
            self.update({ ..self.state, copied: false, })
          },
          2000,
        ),
      )
    } catch {
      _ =>
        if self.mounted {
          self.notify("リンク欄を選択してコピーしてください")
        }
    }
  })
  |> ignore
}

///|
fn StudioController::save_project(self : StudioController) -> Unit {
  if self.save is Some(_) || !truthy(self.document.project) {
    return
  }
  let request = new_controller()
  let project = self.document.project
  self.save = Some(request)
  self.update({ ..self.state, saving: true, })
  @core.from_async(async fn() {
    defer (if self.save
      .map(fn(current) { @core.equal(current, request) })
      .unwrap_or(false) {
      self.save = None
      self.update({ ..self.state, saving: false, })
    })
    try {
      let snapshot = ui_call(self.input._get("services"), "portableProject", [
        project,
        request._get("signal"),
      ])
      if !self.mounted || ui_aborted(request._get("signal")) {
        return
      }
      download_project_snapshot(snapshot)
    } catch {
      error =>
        if self.mounted && !ui_aborted(request._get("signal")) {
          self.notify(
            error_message(
              ui_native_error(error),
              "プロジェクトを保存できませんでした。",
            ),
          )
        }
    }
  })
  |> ignore
}
