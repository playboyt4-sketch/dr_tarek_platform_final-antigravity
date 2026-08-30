const fs = require("node:fs");
const pl = fs.readFileSync("ios/Runner/GoogleService-Info.plist", "utf8");
const gv = (k) => {
  const re = new RegExp("<key>" + k + "</key>\\s*<string>([^<]+)</string>");
  const m = pl.match(re);
  return m ? m[1] : null;
};
const ii = {
  apiKey: gv("API_KEY"),
  appId: gv("GOOGLE_APP_ID"),
  messagingSenderId: gv("GCM_SENDER_ID"),
  storageBucket: gv("STORAGE_BUCKET"),
  projectId: gv("PROJECT_ID"),
  bundleId: gv("BUNDLE_ID"),
};
if (!ii.apiKey || !ii.appId || !ii.bundleId) {
  console.error("plist extraction failed", ii);
  process.exit(1);
}
let opt = fs.readFileSync("lib/firebase_options.dart", "utf8");

// iOS block: replace the six fields individually within the ios options block.
const iosBlockRe =
  /(static const FirebaseOptions ios = FirebaseOptions\([\s\S]*?)(static const FirebaseOptions macos|\}\);)/;
function setField(block, field, value) {
  const re = new RegExp("(\\n\\s*" + field + ": ')[^']*(',)");
  if (!re.test(block)) throw new Error("field not found: " + field);
  return block.replace(re, (m, p1, p2) => p1 + value + p2);
}
opt = opt.replace(iosBlockRe, (m, head) => {
  let b = head;
  b = setField(b, "apiKey", ii.apiKey);
  b = setField(b, "appId", ii.appId);
  b = setField(b, "messagingSenderId", ii.messagingSenderId);
  b = setField(b, "storageBucket", ii.storageBucket);
  b = setField(b, "iosBundleId", ii.bundleId);
  // keep projectId as-is (same project)
  return b;
});
fs.writeFileSync("lib/firebase_options.dart", opt);

// verify
const out = fs.readFileSync("lib/firebase_options.dart", "utf8");
const grab = (name, field) => {
  const re = new RegExp(
    "FirebaseOptions " + name + " = FirebaseOptions\\([\\s\\S]*?" + field + ": '([^']*)'",
  );
  return (out.match(re) || [])[1];
};
console.log(JSON.stringify({
  android_appId: grab("android", "appId"),
  android_apiKey_prefix: (grab("android", "apiKey") || "").slice(0, 10),
  ios_appId: grab("ios", "appId"),
  ios_bundleId: grab("ios", "iosBundleId"),
  web_unchanged: grab("web", "appId"),
}, null, 1));
