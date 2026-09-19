import * as moonbit from "../../../../_build/js/release/build/ui/ui.js";
// React's runtime is external; component layout, hooks and event handling are MoonBit.
const bind = (component) => component;
export const IconButton = bind(moonbit.IconButton);
export const Field = bind(moonbit.Field);
export const NumberInput = bind(moonbit.NumberInput);
export const Modal = bind(moonbit.Modal);
export const Section = bind(moonbit.Section);
