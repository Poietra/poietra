import * as proposals from "../../../_build/js/release/build/proposals/proposals.js";
import { LOCAL_ORIGIN } from "./document.js";
import * as Y from "yjs";
// Runtime schemas are constructed by MoonBit with mizchi's typed Zod bindings.
import * as schemas from "../../../_build/js/release/build/schemas/schemas.js";
const stateProperties = ['x', 'y', 'width', 'height', 'rotation', 'opacity', 'visible', 'fill', 'stroke', 'strokeWidth', 'text', 'fontSize', 'cornerRadius', 'effect'];
export const GENERATED_IMAGE_SIZES = { square: { width: 1024, height: 1024 }, landscape: { width: 1536, height: 1024 }, portrait: { width: 1024, height: 1536 } };
export const MAX_GENERATED_IMAGES = 2;
export const EditProposalSchema = /* @__PURE__ */ schemas.editProposalSchema();
export const placeholderImage = proposals.placeholderImage;
export const withGeneratedImages = proposals.withGeneratedImages;
export const validateStateValue = proposals.validateStateValue;
export function validateProposalForApply(doc, proposal) { proposals.validateProposalForApply(doc, proposal, Y); }
export function applyProposal(doc, proposal, origin = LOCAL_ORIGIN) { proposals.applyProposal(doc, proposal, origin, Y); }
export function compileProposal(doc, project, sceneId, raw, _scope) {
    return proposals.compileProposal(doc, project, sceneId, raw, Y);
}
