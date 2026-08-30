const test = require("firebase-functions-test")();
const { onCall, HttpsError } = require("firebase-functions/v2/https");

const myFunc = onCall((request) => {
  console.log("request.auth:", request.auth);
  return { success: true };
});

const wrapped = test.wrap(myFunc);

wrapped({ data: { foo: "bar" }, auth: { uid: "123" } })
  .then(() => console.log("done"))
  .catch((e) => console.error(e));
