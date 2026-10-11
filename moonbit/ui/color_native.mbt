///|
extern "js" fn eye_dropper_available() -> Bool =
  #|() => typeof globalThis.EyeDropper === 'function'

///|
/// The host owns the browser API and its cancellation; picker state stays typed.
extern "js" fn open_eye_dropper(
  chosen : (String) -> Unit,
  done : () -> Unit,
) -> @core.Any =
  #|(chosen, done) => {
  #|  const controller = new AbortController();
  #|  new EyeDropper().open({ signal: controller.signal }).then(result => {
  #|    if (!controller.signal.aborted) chosen(result.sRGBHex);
  #|  }).catch(() => {}).finally(() => {
  #|    if (!controller.signal.aborted) done();
  #|  });
  #|  return controller;
  #|}
