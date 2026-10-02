///|
fn studio_callbacks(controller : StudioController) -> EditorActions {
  {
    notify: fn(text) { controller.notify(text) },
    select: fn(selection) { controller.select(selection) },
    undo: fn() { controller.undo() },
    redo: fn() { controller.redo() },
    edit_moment: fn(composition) { controller.edit_moment(composition) },
    activate_tool: fn(tool) { controller.activate(tool) },
    play: fn(scope) { controller.play(scope) },
    append_composition: fn() { controller.append() },
    request_text_edit: fn(object, composition) {
      controller.text_edit(object, composition)
    },
    set_selected_ids: fn(ids) {
      controller.update({
        ..controller.state,
        objects: Array::makei(ids.length(), fn(i) { ids[i] }),
      })
    },
    select_objects: fn(ids) {
      controller.choose(Array::makei(ids.length(), fn(i) { ids[i] }))
    },
    seek: fn(time, scope) {
      let scope = scope.unwrap_or_else(fn() {
        if truthy(controller.document.transition) && !controller.state.viewing() {
          SelectedTransition
        } else {
          WholeScene
        }
      })
      controller.seek(time, scope)
    },
    set_playing: fn(value) { if !value { controller.stop() } },
    set_transport_view: fn(value) {
      controller.update({
        ..controller.state,
        cursor: if value {
          ScenePosition
        } else {
          SelectedState
        },
      })
    },
    set_tool: fn(tool) { controller.update({ ..controller.state, tool, }) },
    set_path_editing: fn(value) {
      controller.update({ ..controller.state, path_editing: value, })
    },
    set_panel: fn(panel) { controller.update({ ..controller.state, panel, }) },
  }
}

///|
fn use_studio_effects(
  controller : StudioController,
  panel : @react.ReactRef[@core.Any],
) -> Unit {
  let doc = controller.document
  let state = controller.state
  let input = controller.input
  @react.use_effect(
    fn() {
      controller.mounted = true
      fn() {
        controller.mounted = false
        controller.stop()
        if controller.toast_timer is Some(timer) {
          cancel_timer(timer)
          controller.toast_timer = None
        }
        if controller.copy_timer is Some(timer) {
          cancel_timer(timer)
          controller.copy_timer = None
        }
        if controller.save is Some(request) {
          request._call("abort", []) |> ignore
          controller.save = None
        }
      }
    },
    [input._get("store")],
  )
  @react.use_effect(
    fn() {
      controller.stop()
      fn() { () }
    },
    [
      @core.any(doc.scene_id),
      @core.any(doc.composition),
      @core.any(state.preview_open),
    ],
  )
  @react.use_effect(
    fn() {
      controller.stop()
      controller.position.set(0.0)
      controller.update({
        ..controller.state,
        cursor: SelectedState,
        objects: [],
        path_editing: false,
      })
      fn() { () }
    },
    [@core.any(doc.scene_id)],
  )
  @react.use_effect(
    fn() {
      let scope = match controller.state.transport {
        Playing(scope) | Preparing(_, scope) => scope
        Stopped =>
          if controller.state.cursor == TransitionPosition {
            SelectedTransition
          } else {
            WholeScene
          }
      }
      let end = if scope == SelectedTransition && truthy(doc.transition) {
        doc.selected.map(fn(segment) { segment.start }).unwrap_or(0.0) +
        (doc.transition._get("duration").cast() : Double)
      } else {
        doc.total
      }
      controller.clock = { ..controller.clock, end, }
      if controller.position.time > doc.total {
        controller.position.set(doc.total)
      }
      fn() { () }
    },
    [
      @core.any(doc.total),
      @core.any(state.cursor),
      if doc.selected is Some(segment) {
        @core.any(segment.start)
      } else {
        @core.undefined()
      },
      if truthy(doc.transition) {
        doc.transition._get("duration")
      } else {
        @core.undefined()
      },
    ],
  )
  @react.use_effect(
    fn() {
      if truthy(doc.scene) {
        input
        ._get("store")
        ._call("presence", [
          host_record({
            "sceneId": @core.any(doc.scene_id),
            "compositionId": @core.any(doc.composition),
            "selectedIds": @core.any(host_array(doc.objects)),
          }),
        ])
        |> ignore
      }
      fn() { () }
    },
    [
      @core.any(doc.scene_id),
      @core.any(doc.composition),
      @core.any(doc.objects.join(",")),
      input._get("store"),
    ],
  )
  @react.use_effect(
    fn() {
      if state.text_edit is Some(target) {
        if doc.scene_id == target.scene &&
          doc.selection is CompositionSelection(_) &&
          doc.composition == target.composition &&
          doc.objects == [target.object] &&
          !state.viewing() &&
          state.panel == DesignPanel &&
          panel.get_current() is Some(panel) {
          let field = panel._call("querySelector", [
            @core.any(
              "textarea[aria-label=\"Text content\"], textarea[aria-label=\"LaTeX expression\"]",
            ),
          ])
          if truthy(field) {
            field._call("focus", [
              host_record({ "preventScroll": @core.any(true) }),
            ])
            |> ignore
            field._call("select", []) |> ignore
          }
        }
        controller.update({ ..controller.state, text_edit: None, })
      }
      fn() { () }
    },
    [
      @core.any(state.text_edit),
      @core.any(doc.scene_id),
      @core.any(doc.composition),
      @core.any(doc.objects.join(",")),
      @core.any(state.cursor),
      @core.any(state.panel),
    ],
  )
  let preparation = use_render_preparation(doc.scene)
  @react.use_effect(
    fn() {
      let current = Ref(true)
      if truthy(doc.scene) {
        @core.from_async(async fn() {
          try {
            ui_call(input._get("renderer"), "prepareScene", [doc.scene])
            |> ignore
            if current.val && controller.mounted {
              controller.update({
                ..controller.state,
                render_revision: controller.state.render_revision + 1,
                render_error: "",
              })
            }
          } catch {
            error =>
              if current.val && controller.mounted {
                controller.update({
                  ..controller.state,
                  render_error: error_message(
                    ui_native_error(error),
                    "描画を準備できませんでした。",
                  ),
                })
              }
          }
        })
        |> ignore
      }
      fn() { current.val = false }
    },
    [
      @core.any(preparation),
      @core.any(doc.scene_id),
      input._get("renderer"),
      @core.any(state.render_attempt),
    ],
  )
  @react.use_effect(
    fn() {
      if !state.playing() {
        return fn() { () }
      }
      let request = Ref(@core.undefined())
      fn tick(now : Double) -> Unit {
        if !controller.mounted || !controller.state.playing() {
          return
        }
        let next = controller.clock.position + now - controller.clock.time
        controller.position.set(next.min(controller.clock.end))
        if next >= controller.clock.end {
          controller.update({ ..controller.state, transport: Stopped, })
        }
        if next < controller.clock.end {
          request.val = @core.global_this()._call("requestAnimationFrame", [
            @core.any(tick),
          ])
        }
      }
      request.val = @core.global_this()._call("requestAnimationFrame", [
        @core.any(tick),
      ])
      fn() {
        @core.global_this()._call("cancelAnimationFrame", [request.val])
        |> ignore
      }
    },
    [@core.any(state.playing())],
  )
}
