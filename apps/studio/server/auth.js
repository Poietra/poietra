import * as moon from "../../../_build/js/release/build/auth_service/auth_service.js";
export const AUTH_FLOW_TTL = 10 * 60 * 1000;
export const AUTH_SESSION_TTL = 7 * 24 * 60 * 60 * 1000;
export const ACCOUNT_PROJECT_LIMIT = 500;
export const AuthService = moon.authServiceClass();
export const authHash = moon.authHash;
export const safeReturnTo = moon.safeReturnTo;
