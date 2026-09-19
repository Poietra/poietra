import { createElement } from "react";
import { portableProject } from "../editor/images.js";
import { createProjectRoom } from "../editor/projects.js";
import { ProjectDialog as MoonProjectDialog } from "../../../../_build/js/release/build/ui/ui.js";
import "./ProjectDialog.css";
const services = { portableProject, createProjectRoom };
export const ProjectDialog = props => createElement(MoonProjectDialog, { ...props, services });
