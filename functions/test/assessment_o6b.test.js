/**
 * O6-B assessment contract tests (Option B: results only after final submit).
 *
 * Offline pure-function suite: importing ../lib/index.js must not touch the
 * network (same pattern as exam_grading.test.js — only pure helpers invoked).
 *
 * Proves:
 *  1. Sanitized delivery never contains answer keys, explanations, or scores.
 *  2. Type/text/options/marks fallbacks behave deterministically.
 *  3. The getAssessmentQuestions callable export exists (no evaluate endpoint
 *     exists by design — immediate per-question feedback is removed).
 */
const assert = require("node:assert/strict");

const lib = require("../lib/index.js");
const {
  normalizeAssessmentQuestionType,
  sanitizeAssessmentQuestion,
  getAssessmentQuestions,
  submitAssessmentAttempt,
} = lib;

function run() {
  // 1) Type normalization.
  assert.equal(normalizeAssessmentQuestionType("MCQ"), "mcq");
  assert.equal(normalizeAssessmentQuestionType("mcq"), "mcq");
  assert.equal(normalizeAssessmentQuestionType("True / False"), "true-false");
  assert.equal(normalizeAssessmentQuestionType("truefalse"), "true-false");
  assert.equal(normalizeAssessmentQuestionType("Essay"), "essay");
  assert.equal(normalizeAssessmentQuestionType("unknown-type"), "mcq");
  assert.equal(normalizeAssessmentQuestionType(null), "mcq");

  // 2) Key/explanation/score stripping — the O6-B core guarantee.
  const bank = {
    question_text: "What is 2 + 2?",
    options: ["3", "4", "5"],
    correct_answer: "4",
    correctAnswer: "4",
    explanation: "Basic arithmetic",
    score: 999,
  };
  const out = sanitizeAssessmentQuestion(
    {questionId: "q1", marks: 2, order: 0},
    bank,
  );
  assert.deepEqual(out, {
    id: "q1",
    type: "mcq",
    text: "What is 2 + 2?",
    options: ["3", "4", "5"],
    marks: 2,
    order: 0,
  });
  const serialized = JSON.stringify(out);
  for (const forbidden of [
    "correct_answer",
    "correctAnswer",
    "explanation",
    "Basic arithmetic",
    "999",
  ]) {
    assert.ok(
      !serialized.includes(forbidden),
      `sanitized payload must not contain ${forbidden}`,
    );
  }

  // 3) Display-field fallbacks + marks default + null bank.
  const alt = sanitizeAssessmentQuestion(
    {questionId: "q2", marks: 0, order: 3},
    {text: "TF?", choices: ["True", "False"], type: "True / False"},
  );
  assert.deepEqual(alt, {
    id: "q2",
    type: "true-false",
    text: "TF?",
    options: ["True", "False"],
    marks: 1,
    order: 3,
  });
  assert.equal(
    sanitizeAssessmentQuestion({questionId: "q9", marks: 1, order: 0}, null),
    null,
  );
  const nonStrings = sanitizeAssessmentQuestion(
    {questionId: "q3", marks: 1, order: 0},
    {question_text: "Q?", options: ["ok", 42, null]},
  );
  assert.deepEqual(nonStrings.options, ["ok"]);

  // 4) Contract surface: delivery endpoint exists, submit preserved,
  //    and no per-question evaluation endpoint exists by design.
  assert.ok(getAssessmentQuestions, "getAssessmentQuestions must be exported");
  assert.ok(
    submitAssessmentAttempt,
    "submitAssessmentAttempt must remain exported",
  );
  assert.equal(
    lib.evaluateQuestionAnswer,
    undefined,
    "no immediate-feedback endpoint may exist under O6-B",
  );

  console.log("assessment_o6b.test: PASS");
}

try {
  run();
} catch (e) {
  console.error("assessment_o6b.test: FAIL", e);
  process.exitCode = 1;
}
