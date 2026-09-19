///|
fn studio_callbacks(controller : StudioController) -> @core.Any {
  host_record({
    "notify": @core.any(fn(text : String) { controller.notify(text) }),
    "select": @core.any(fn(value : @core.Any) {
      controller.select(studio_selection(value))
    }),
    "undo": @core.any(fn() { controller.undo() }),
    "redo": @core.any(fn() { controller.redo() }),
    "editMoment": @core.any(fn(composition : @core.Any) {
      controller.edit_moment(truthy(composition))
    }),
    "activateTool": @core.any(fn(value : String) {
      controller.activate(studio_tool(value))
    }),
    "play": @core.any(fn(value : @core.Any) {
      controller.play(studio_scope(value))
    }),
    "setSelectedIds": @core.any(fn(ids : FixedArray[String]) {
      controller.update({
        ..controller.state,
        objects: Array::makei(ids.length(), fn(i) { ids[i] }),
      })
    }),
    "setPlaying": @core.any(fn(value : Bool) { if !value { controller.stop() } }),
    "setTransportView": @core.any(fn(value : Bool) {
      controller.update({
        ..controller.state,
        cursor: if value {
          ScenePosition
        } else {
          SelectedState
        },
      })
    }),
    "setTool": @core.any(fn(value : String) {
      controller.update({ ..controller.state, tool: studio_tool(value), })
    }),
    "setPathEditing": @core.any(fn(value : Bool) {
      controller.update({ ..controller.state, path_editing: value, })
    }),
    "setRightTab": @core.any(fn(value : String) {
      controller.update({
        ..controller.state,
        panel: if value == "assistant" {
          ChatPanel
        } else {
          DesignPanel
        },
      })
    }),
  })
}

///|
fn use_studio_effects(
  controller : StudioController,
  chat : FixedArray[@core.Any],
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
      if state.panel == ChatPanel && !state.preview_open {
        let last : String? = if chat.is_empty() {
          None
        } else {
          Some(chat[chat.length() - 1]._get("id").cast())
        }
        controller.update({ ..controller.state, last_read: last, })
      }
      fn() { () }
    },
    [@core.any(state.panel), @core.any(state.preview_open), @core.any(chat)],
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
      controller.update({
        ..controller.state,
        cursor: SelectedState,
        playhead: 0.0,
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
        (if truthy(doc.selected) {
          doc.selected._get("start").cast()
        } else {
          0.0
        }) +
        (doc.transition._get("duration").cast() : Double)
      } else {
        doc.total
      }
      controller.clock = { ..controller.clock, end, }
      if controller.state.playhead > doc.total {
        controller.update({ ..controller.state, playhead: doc.total, })
      }
      fn() { () }
    },
    [
      @core.any(doc.total),
      @core.any(state.cursor),
      if truthy(doc.selected) {
        doc.selected._get("start")
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
    [doc.scene, input._get("renderer")],
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
        controller.update({
          ..controller.state,
          playhead: next.min(controller.clock.end),
          transport: if next >= controller.clock.end {
            Stopped
          } else {
            controller.state.transport
          },
        })
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
