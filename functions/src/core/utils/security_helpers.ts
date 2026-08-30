import { CallableOptions } from "firebase-functions/v2/https";

export const SECURE_CALL_OPTS: CallableOptions = {
  enforceAppCheck: true,
};
