/**
 * Assessment grading engine — pure unit tests (no emulator required).
 *
 * The legacy per-question `gradeAssessmentQuestion`, `setAssessmentRelease`
 * and `releaseDueAssessmentResults` callables were removed from the backend;
 * grading now lives in the pure `gradeObjectiveAnswers` helper consumed by
 * `submitAssessmentAttempt` / `submitExamAttempt`. This file verifies that
 * engine plus the presence of both live submit callables.
 */
const test = require("firebase-functions-test")({
  projectId: "dr-tarek-platform-functions-test",
});

const assert = require("node:assert/strict");

const adminMock = {
  initializeApp: () => ({}),
  getFirestore: () => ({
    collection: () => ({
      doc: () => ({
        get: async () => ({exists: false}),
        update: async () => {},
        set: async () => {},
      }),
      where: () => ({
        where: () => ({
          limit: () => ({get: async () => ({empty: true, docs: []})}),
        }),
        limit: () => ({get: async () => ({empty: true, docs: []})}),
      }),
      add: async () => ({id: "mock-doc"}),
    }),
  }),
  FieldValue: {serverTimestamp: () => ({_serverTimestamp: true})},
  Timestamp: {now: () => ({toMillis: () => Date.now()})},
  getAuth: () => ({
    updateUser: async () => {},
    getUser: async () => ({customClaims: {}}),
    setCustomUserClaims: async () => {},
  }),
  getMessaging: () => ({}),
  getStorage: () => ({}),
};

const Module = require("node:module");
const originalRequire = Module.prototype.require;
Module.prototype.require = function (id) {
  if (id === "firebase-admin/firestore") {
    return {
      getFirestore: adminMock.getFirestore,
      FieldValue: adminMock.FieldValue,
      Timestamp: adminMock.Timestamp,
    };
  }
  if (id === "firebase-admin/auth") return {getAuth: adminMock.getAuth};
  if (id === "firebase-admin/messaging") return {getMessaging: adminMock.getMessaging};
  if (id === "firebase-admin/storage") return {getStorage: adminMock.getStorage};
  if (id === "firebase-admin/app") return {initializeApp: adminMock.initializeApp};
  return originalRequire.apply(this, arguments);
};

let functions;
try {
  functions = require("../lib/index.js");
} catch (error) {
  console.error("Failed to load functions:", error);
  process.exit(1);
}

function bank(entries) {
  return new Map(
    entries.map(([id, type, answer]) => [id, {questionType: type, correctAnswer: answer}]),
  );
}

async function run() {
  let passed = 0;
  function check(name, fn) {
    try {
      fn();
      passed++;
      console.log(`ok - ${name}`);
    } catch (err) {
      console.error(`FAIL - ${name}: ${err.message}`);
      process.exitCode = 1;
    }
  }

  // Live submit callables are exported (exam path aliases the engine).
  check("submitAssessmentAttempt is exported", () => {
    assert.equal(typeof functions.submitAssessmentAttempt, "function");
  });
  check("submitExamAttempt is exported", () => {
    assert.equal(typeof functions.submitExamAttempt, "function");
  });

  const links = [
    {questionId: "q1", marks: 2},
    {questionId: "q2", marks: 3},
  ];

  check("all correct answers score full marks", () => {
    const res = functions.gradeObjectiveAnswers(
      links,
      bank([["q1", "mcq", "Cairo"], ["q2", "true_false", "true"]]),
      {q1: "Cairo", q2: "true"},
    );
    assert.equal(res.score, 5);
    assert.equal(res.totalMarks, 5);
    assert.equal(res.hasEssay, false);
  });

  check("grading is case-insensitive and trimmed", () => {
    const res = functions.gradeObjectiveAnswers(
      links,
      bank([["q1", "mcq", "Cairo"], ["q2", "true_false", "true"]]),
      {q1: "  cairo ", q2: "TRUE"},
    );
    assert.equal(res.score, 5);
  });

  check("wrong answers score zero but count total marks", () => {
    const res = functions.gradeObjectiveAnswers(
      links,
      bank([["q1", "mcq", "Cairo"], ["q2", "true_false", "true"]]),
      {q1: "Alex", q2: "false"},
    );
    assert.equal(res.score, 0);
    assert.equal(res.totalMarks, 5);
  });

  check("essay questions flag manual grading without scoring", () => {
    const res = functions.gradeObjectiveAnswers(
      [...links, {questionId: "q3", marks: 5}],
      bank([["q1", "mcq", "Cairo"], ["q2", "mcq", "Nile"], ["q3", "essay", ""]]),
      {q1: "Cairo", q2: "Nile", q3: "long text"},
    );
    assert.equal(res.hasEssay, true);
    assert.equal(res.score, 5);
    assert.equal(res.totalMarks, 10);
  });

  check("unknown question links are reported, not scored", () => {
    const res = functions.gradeObjectiveAnswers(
      [...links, {questionId: "ghost", marks: 4}],
      bank([["q1", "mcq", "Cairo"], ["q2", "mcq", "Nile"]]),
      {q1: "Cairo", q2: "Nile"},
    );
    assert.equal(res.missingQuestions, 1);
    assert.equal(res.score, 5);
    assert.equal(res.totalMarks, 5);
  });

  check("empty submission scores zero", () => {
    const res = functions.gradeObjectiveAnswers(
      links,
      bank([["q1", "mcq", "Cairo"], ["q2", "mcq", "Nile"]]),
      {},
    );
    assert.equal(res.score, 0);
    assert.equal(res.totalMarks, 5);
  });

  test.cleanup();

  if (process.exitCode === 1) {
    console.error("result_release tests FAILED");
    process.exit(1);
  }
  console.log(`result_release.test: PASS - All ${passed} checks passed.`);
}

run();
