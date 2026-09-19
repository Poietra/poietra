///|
priv struct HomeState {
  locale : @site.Locale
  busy : @site.Template?
  failed : Bool
  resume_url : String?
}

///|
priv struct HomeController {
  mut mounted : Bool
  mut request : @core.Any?
  mut view : HomeState
  publish : (HomeState) -> Unit
  runtime : @core.Any
}

///|
fn HomeController::update(self : HomeController, view : HomeState) -> Unit {
  if self.mounted {
    self.view = view
    (self.publish)(view)
  }
}

///|
fn HomeController::current(self : HomeController, request : @core.Any) -> Bool {
  self.mounted &&
  self.request
  .map(fn(current) { @core.equal(current, request) })
  .unwrap_or(false) &&
  !(request._get("signal")._get("aborted").cast() : Bool)
}

///|
fn HomeController::cancel(self : HomeController) -> Unit {
  let request = self.request
  self.request = None
  if request is Some(request) {
    request._call("abort", []) |> ignore
  }
  self.update({ ..self.view, busy: None, })
}

///|
async fn home_call(
  owner : @core.Any,
  name : String,
  arguments : FixedArray[@core.Any],
) -> @core.Any {
  let result = @core.throwable(fn() { owner._call(name, arguments) })
  @core.Promise::resolve(result).wait()
}

///|
async fn HomeController::create(
  self : HomeController,
  template : @site.Template,
) -> Unit {
  if !self.mounted || self.request is Some(_) {
    return
  }
  let request = @core.new(@core.global_this()._get("AbortController"), [])
  self.request = Some(request)
  self.update({ ..self.view, busy: Some(template), failed: false, })
  defer (if self.current(request) {
    self.request = None
    self.update({ ..self.view, busy: None, })
  })
  try {
    let projects = @core.from_async(async fn() {
      home_call(self.runtime, "loadProjects", [])
    })
    let samples = @core.from_async(async fn() {
      home_call(self.runtime, "loadSamples", [])
    })
    let loaded = @core.Promise::all([projects, samples]).wait()
    if !self.current(request) {
      return
    }
    let project = @core.throwable(fn() {
      if template == Example {
        return loaded[1]._call("makeDemoProject", [])
      }
      let uuid : String = @core.global_this()
        ._get("crypto")
        ._call("randomUUID", [])
        .cast()
      let id = "scene_" +
        uuid[:8].to_owned() +
        uuid[9:13].to_owned() +
        uuid[14:18].to_owned()
      @core.from_entries([
        ("version", @core.any(1)),
        ("name", @core.any("Untitled project")),
        ("sceneOrder", @core.any(([id] : FixedArray[String]))),
        (
          "scenes",
          @core.from_entries([
            (
              id,
              loaded[1]._call("makeBlankScene", [
                @core.any(id),
                @core.any("Scene 1"),
              ]),
            ),
          ]),
        ),
      ])
    })
    let url = home_call(loaded[0], "createProjectRoom", [
      project,
      request._get("signal"),
    ])
    if !self.current(request) {
      return
    }
    let room : String = url
      ._get("searchParams")
      ._call("get", [@core.any("room")])
      .cast()
    @core.throwable(fn() {
      @core.global_this()
      ._get("location")
      ._call("assign", [@core.any(@shell.room_link(room))])
    })
    |> ignore
  } catch {
    _ =>
      if self.current(request) {
        self.update({ ..self.view, failed: true, })
      }
  }
}

///|
pub fn home(input : @core.Any) -> @react.Element {
  let (state, publish) = @react.use_state_lazy(fn() {
    let locale = optional_string(input._get("initialLocale")).unwrap_or_else(
      @shell.get_locale,
    )
    HomeState::{
      locale: @site.locale(locale).unwrap_or(English),
      busy: None,
      failed: false,
      resume_url: None,
    }
  })
  let ref_ : @react.ReactRef[HomeController] = @react.use_ref(None)
  let controller = match ref_.get_current() {
    Some(controller) => controller
    None => {
      let controller = {
        mounted: false,
        request: None,
        view: state,
        publish,
        runtime: input._get("runtime"),
      }
      ref_.set_current(Some(controller))
      controller
    }
  }
  @react.use_effect(
    fn() {
      controller.mounted = true
      fn() {
        controller.mounted = false
        controller.cancel()
      }
    },
    [],
  )
  @react.use_effect(
    fn() {
      @shell.apply_page_language(@site.locale_name(state.locale))
      fn() {  }
    },
    [@core.any(state.locale)],
  )
  @react.use_effect(
    fn() {
      let language_changed = fn() {
        controller.update({
          ..controller.view,
          locale: @site.locale(@shell.get_locale()).unwrap_or(English),
        })
      }
      language_changed()
      let room = optional_string(@shell.last_room())
      controller.update({
        ..controller.view,
        resume_url: room.map(@shell.room_link),
      })
      let window = @core.global_this()._get("window")
      window._call("addEventListener", [
        @core.any("languagechange"),
        @core.any(language_changed),
      ])
      |> ignore
      fn() {
        window._call("removeEventListener", [
          @core.any("languagechange"),
          @core.any(language_changed),
        ])
        |> ignore
      }
    },
    [],
  )
  landing({
    copy: @site.landing_copy(state.locale),
    locale: state.locale,
    busy: state.busy,
    error: if state.failed {
      @site.page_copy(state.locale).projectError
    } else {
      ""
    },
    resume_url: state.resume_url,
    start: fn(template) {
      @core.from_async(async fn() { controller.create(template) }) |> ignore
    },
    cancel: fn() { controller.cancel() },
  })
}

///|
pub fn home_tree(locale : @core.Any, runtime : @core.Any) -> @react.Element {
  @shell.protect(
    @react.jsx(@core.any(home), [], props={
      "initialLocale": locale,
      "runtime": runtime,
    }),
  )
}

///|
pub fn open_home(container : @core.Any, runtime : @core.Any) -> Unit {
  let locale = optional_string(container._get("dataset")._get("locale"))
  if locale is Some(name) && @site.locale(name) is Some(_) {
    @client.hydrate_root(container.cast(), home_tree(@core.any(name), runtime))
    |> ignore
  } else {
    @client.create_root(container.cast()).render(
      home_tree(@core.undefined(), runtime),
    )
  }
}
