///|
priv enum OutputPhase {
  Pending
  Writing
  Finalizing
  Finished
}

///|
priv struct OutputOwner {
  value : @core.Any
  mut phase : OutputPhase
}

///|
priv struct Resources {
  mut canvas : @core.Any?
  mut painter : @core.Any?
  mut video : @core.Any?
  mut audio : @core.Any?
  mut mixer : @browser_media.AudioMixer?
  mut output : OutputOwner?
}

///|
fn quietly(owner : @core.Any, operation : String) -> Unit {
  try @core.throwable(fn() { owner._call(operation, []) }) |> ignore catch {
    _ => ()
  }
}

///|
async fn Resources::release(self : Resources) -> Unit {
  if self.output is Some(output) {
    self.output = None
    let unfinished = match output.phase {
      Pending | Writing | Finalizing => true
      Finished => false
    }
    if unfinished &&
      !@core.equal(output.value._get("state"), @core.any("finalized")) {
      try invoke(output.value, "cancel", []) |> ignore catch {
        _ => ()
      }
    }
  }
  if self.mixer is Some(mixer) {
    self.mixer = None
    mixer.dispose()
  }
  if self.audio is Some(source) {
    self.audio = None
    quietly(source, "close")
  }
  if self.video is Some(source) {
    self.video = None
    quietly(source, "close")
  }
  if self.painter is Some(painter) {
    self.painter = None
    quietly(painter, "dispose")
  }
  if self.canvas is Some(canvas) {
    self.canvas = None
    canvas._set("width", @core.any(0))
    canvas._set("height", @core.any(0))
  }
}

///|
priv enum Stage {
  Preparation
  AudioPreparation
  ScenePreparation
  PainterPreparation
  EncoderStart
  VideoFrames
  AudioFrames
  Finalize
}

///|
fn Stage::label(self : Stage) -> String {
  match self {
    Preparation => "書き出しの準備"
    AudioPreparation => "音声の準備"
    ScenePreparation => "フォントと数式の準備"
    PainterPreparation => "描画エンジンの準備"
    EncoderStart => "エンコーダーの開始"
    VideoFrames => "動画フレームの描画とエンコード"
    AudioFrames => "音声の混合とエンコード"
    Finalize => "動画ファイルの仕上げ"
  }
}

///|
fn contextual_error(error : Error, stage : Stage, signal : @core.Any) -> Error {
  let value = native_error(error)
  if aborted(signal) ||
    (
      !@core.is_nullish(value) &&
      @core.equal(value._get("name"), @core.any("AbortError"))
    ) {
    return Native(export_abort_error())
  }
  let detail : String = if @core.instanceof_(
      value,
      @core.global_this()._get("Error"),
    ) {
    value._get("message").cast()
  } else {
    value.to_string()
  }
  Native(
    @core.new(@core.global_this()._get("Error"), [
      @core.any("\{stage.label()}に失敗しました。\{detail}"),
      @core.from_entries([("cause", value)]),
    ]),
  )
}

///|
fn report(callback : @core.Any, progress : Double) -> Unit raise {
  if !@core.is_nullish(callback) {
    @core.throwable(fn() { callback._invoke([@core.any(progress)]) }) |> ignore
  }
}
