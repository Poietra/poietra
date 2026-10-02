///|
/// Compatibility with the public JS EditorContextValue. Keep string keys and
/// enum/callback conversion here, outside internal component communication.
fn read_native_editor(input : @core.Any) -> EditorView {
  let selected : FixedArray[String] = input._get("selectedIds").cast()
  {
    store: input._get("store"),
    scene: input._get("scene"),
    selection: studio_selection(input._get("selection")),
    composition_id: input._get("compositionId").cast(),
    selected_ids: selected,
    tool: studio_tool(input._get("tool").cast()),
    kernel: input._get("kernel"),
    renderer: input._get("renderer"),
    create_frame_painter: input._get("createFramePainter"),
    position_source: if truthy(input._get("positionSource")) {
      Some(input._get("positionSource").cast())
    } else {
      None
    },
    playhead: optional_number(input, "playhead", 0.0),
    peers: if @core.is_nullish(input._get("peers")) {
      []
    } else {
      input._get("peers").cast()
    },
    playing: truthy(input._get("playing")),
    viewing_playback: truthy(input._get("viewingPlayback")),
    preview_scope: studio_scope(input._get("previewScope")),
    path_editing: truthy(input._get("pathEditing")),
    actions: read_native_editor_actions(input),
  }
}

///|
fn native_editor_actions(actions : EditorActions) -> @core.Any {
  host_record({
    "notify": @core.any(actions.notify),
    "select": @core.any(fn(value : @core.Any) {
      (actions.select)(studio_selection(value))
    }),
    "setSelectedIds": @core.any(actions.select_objects),
    "chooseObjects": @core.any(actions.select_objects),
    "appendComposition": @core.any(actions.append_composition),
    "requestTextEdit": @core.any(actions.request_text_edit),
    "setTool": @core.any(fn(tool : String) {
      (actions.set_tool)(studio_tool(tool))
    }),
    "activateTool": @core.any(fn(tool : String) {
      (actions.activate_tool)(studio_tool(tool))
    }),
    "seek": @core.any(fn(time : Double, scope : @core.Any) {
      (actions.seek)(
        time,
        if @core.is_undefined(scope) {
          None
        } else {
          Some(studio_scope(scope))
        },
      )
    }),
    "play": @core.any(fn(scope : @core.Any) {
      (actions.play)(studio_scope(scope))
    }),
    "setPlaying": @core.any(actions.set_playing),
    "setTransportView": @core.any(actions.set_transport_view),
    "setPathEditing": @core.any(actions.set_path_editing),
    "setRightTab": @core.any(fn(panel : String) {
      (actions.set_panel)(
        if panel == "assistant" {
          ChatPanel
        } else {
          DesignPanel
        },
      )
    }),
    "editMoment": @core.any(fn(composition : @core.Any) {
      (actions.edit_moment)(truthy(composition))
    }),
    "undo": @core.any(actions.undo),
    "redo": @core.any(actions.redo),
  })
}

///|
fn native_editor_view(view : EditorView, callbacks : @core.Any) -> @core.Any {
  let value = ui_shallow_copy(callbacks)
  for
    (key, field) in [
      ("store", view.store),
      ("scene", view.scene),
      ("selection", view.selection.native()),
      ("compositionId", @core.any(view.composition_id)),
      ("selectedIds", @core.any(view.selected_ids)),
      ("tool", @core.any(studio_tool_name(view.tool))),
      ("kernel", view.kernel),
      ("renderer", view.renderer),
      ("createFramePainter", view.create_frame_painter),
      (
        "positionSource",
        match view.position_source {
          Some(position) => @core.any(position)
          None => @core.undefined()
        },
      ),
      ("playhead", @core.any(view.playhead)),
      ("peers", @core.any(view.peers)),
      ("playing", @core.any(view.playing)),
      ("viewingPlayback", @core.any(view.viewing_playback)),
      ("previewScope", @core.any(view.preview_scope.name())),
      ("pathEditing", @core.any(view.path_editing)),
    ] {
    value._set(key, field)
  }
  value
}

///|
fn read_native_controls(input : @core.Any) -> EditorControls {
  {
    store: input._get("store"),
    scene: input._get("scene"),
    composition_id: input._get("compositionId").cast(),
    active_ids: input._get("activeIds").cast(),
    playing: truthy(input._get("playing")),
    viewing_playback: truthy(input._get("transportView")),
    has_transition: !@core.is_nullish(input._get("transition")),
    composing: input._get("composing").cast(),
    paste_in_place: input._get("pasteInPlace").cast(),
    actions: read_native_editor_actions(input),
  }
}

///|
fn read_import_point(point : @core.Any) -> @scene.Point? {
  if @core.is_nullish(point) {
    None
  } else {
    Some({ x: point._get("x").cast(), y: point._get("y").cast(), })
  }
}

///|
fn native_import_view(view : ImportView) -> @core.Any {
  let import_files = fn(files : FixedArray[@core.Any], point : @core.Any) {
    (view.import_files)(files, read_import_point(point))
  }
  host_record({
    "imageRequest": view.image_request.as_any(),
    "mediaRequest": view.media_request.as_any(),
    "importingImage": @core.any(view.importing_image),
    "setImportingImage": @core.any(view.set_importing_image),
    "importError": @core.any(view.error),
    "setImportError": @core.any(view.set_error),
    "mediaImport": match view.media_import {
      None => @core.null()
      Some(progress) =>
        host_record({
          "name": @core.any(progress.name),
          "index": @core.any(progress.index),
          "count": @core.any(progress.count),
          "progress": @core.any(progress.progress),
          "phase": @core.any(
            match progress.phase {
              ReadAsset => "reading"
              ReadWaveform => "waveform"
              TransferAsset => "uploading"
              SaveAsset => "saving"
            },
          ),
        })
    },
    "importImages": @core.any(fn(
      files : FixedArray[@core.Any],
      point : @core.Any,
    ) {
      (view.import_images)(files, read_import_point(point))
    }),
    "importMediaFiles": @core.any(import_files),
    "importFiles": @core.any(import_files),
    "cancel": @core.any(view.cancel),
  })
}

///|
fn native_image_rehost(
  services : @core.Any,
) -> async (FixedArray[@core.Any], String, @core.Any) -> Unit {
  async fn(objects, room, signal) {
    ui_call(services, "rehostImageAssets", [
      @core.any(objects),
      @core.any(room),
      signal,
    ])
    |> ignore
  }
}

///|
fn read_native_clipboard(input : @core.Any) -> ClipboardInput {
  {
    controls: read_native_controls(input),
    image_request: input._get("imageRequest").cast(),
    media_request: input._get("mediaRequest").cast(),
    set_importing_image: input._get("setImportingImage").cast(),
    import_files: fn(files, point) {
      input
      ._get("importFiles")
      ._invoke([
        @core.any(files),
        match point {
          Some(point) => stage_point(point)
          None => @core.undefined()
        },
      ])
      |> ignore
    },
    rehost_images: native_image_rehost(input),
  }
}

///|
fn read_native_editor_actions(input : @core.Any) -> EditorActions {
  let choose : (FixedArray[String]) -> Unit = input
    ._get("setSelectedIds")
    .cast()
  {
    notify: input._get("notify").cast(),
    select: fn(selection) {
      input._get("select")._invoke([selection.native()]) |> ignore
    },
    select_objects: choose,
    set_selected_ids: choose,
    append_composition: input._get("appendComposition").cast(),
    request_text_edit: input._get("requestTextEdit").cast(),
    set_tool: fn(tool) {
      input._get("setTool")._invoke([@core.any(studio_tool_name(tool))])
      |> ignore
    },
    activate_tool: fn(tool) {
      input._get("activateTool")._invoke([@core.any(studio_tool_name(tool))])
      |> ignore
    },
    seek: fn(time, scope) {
      input
      ._get("seek")
      ._invoke([
        @core.any(time),
        match scope {
          Some(scope) => @core.any(scope.name())
          None => @core.undefined()
        },
      ])
      |> ignore
    },
    play: fn(scope) {
      input._get("play")._invoke([@core.any(scope.name())]) |> ignore
    },
    set_playing: input._get("setPlaying").cast(),
    set_transport_view: input._get("setTransportView").cast(),
    set_path_editing: input._get("setPathEditing").cast(),
    set_panel: fn(panel) {
      input
      ._get("setRightTab")
      ._invoke([
        @core.any(if panel == ChatPanel { "assistant" } else { "properties" }),
      ])
      |> ignore
    },
    edit_moment: input._get("editMoment").cast(),
    undo: input._get("undo").cast(),
    redo: input._get("redo").cast(),
  }
}
