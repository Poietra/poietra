import { clsx } from "clsx";
import { twMerge } from "tailwind-merge";
export function cn(...inputs) { return twMerge(clsx(inputs)); }
export { download } from "../../../../_build/js/release/build/ui/ui.js";
