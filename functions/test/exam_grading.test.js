/**
 * Unit tests for the server-side objective exam grader.
 *
 * gradeObjectiveAnswers is a pure exported function from src/index.ts and
 * implements the approved 05 Database grading model:
 *   - MCQ / True-False answers are compared against question_bank
 *     correct_answer (case/whitespace tolerant).
 *   - Essay questions contribute marks to the total but never to the
 *     automatic score (needs_manual_grading).
 *   - Linked questions missing from question_bank are excluded from the
 *     total so authoring errors cannot silently penalize students.
 *   - Missing/invalid marks default to 1.
 */
const assert = require("node:assert/strict");

const {gradeObjectiveAnswers} = require("../lib/index.js");

function run() {
  // 1) All correct (MCQ + True/False), case/whitespace normalization.
  const allCorrect = gradeObjectiveAnswers(
    [
      {questionId: "q1", marks: 2},
      {questionId: "q2", marks: 3},
    ],
    new Map([
      ["q1", {questionType: "mcq", correctAnswer: "Cairo"}],
      ["q2", {questionType: "true_false", correctAnswer: "TRUE"}],
    ]),
    {q1: "  cairo ", q2: "true"},
  );
  assert.deepEqual(
    {score: allCorrect.score, totalMarks: allCorrect.totalMarks, hasEssay: allCorrect.hasEssay},
    {score: 5, totalMarks: 5, hasEssay: false},
    "all-correct objective attempt must score full marks",
  );

  // 2) All wrong -> zero score, total preserved.
  const allWrong = gradeObjectiveAnswers(
    [{questionId: "q1", marks: 4}],
    new Map([["q1", {questionType: "mcq", correctAnswer: "a"}]]),
    {q1: "b"},
  );
  assert.equal(allWrong.score, 0, "wrong answer must score zero");
  assert.equal(allWrong.totalMarks, 4);

  // 3) Client-sent inflated scores cannot exist: grader derives from answers.
  const tamper = gradeObjectiveAnswers(
    [{questionId: "q1", marks: 10}],
    new Map([["q1", {questionType: "mcq", correctAnswer: "x"}]]),
    {q1: "wrong"},
  );
  assert.equal(tamper.score, 0, "tampered wrong answer must not earn marks");

  // 4) Mixed essay: essay marks count in total, never in auto score.
  const mixed = gradeObjectiveAnswers(
    [
      {questionId: "q1", marks: 5},
      {questionId: "q2", marks: 5},
    ],
    new Map([
      ["q1", {questionType: "mcq", correctAnswer: "yes"}],
      ["q2", {questionType: "essay", correctAnswer: ""}],
    ]),
    {q1: "YES", q2: "any long essay text"},
  );
  assert.equal(mixed.score, 5);
  assert.equal(mixed.totalMarks, 10);
  assert.equal(mixed.hasEssay, true);

  // 5) Missing question excluded from total; invalid marks default to 1.
  const withMissing = gradeObjectiveAnswers(
    [
      {questionId: "known", marks: Number.NaN},
      {questionId: "ghost", marks: 7},
    ],
    new Map([["known", {questionType: "mcq", correctAnswer: "z"}]]),
    {known: "Z"},
  );
  assert.equal(withMissing.score, 1);
  assert.equal(withMissing.totalMarks, 1);
  assert.equal(withMissing.missingQuestions, 1);

  console.log(
    "exam_grading.test: PASS — objective grading, normalization, essays, missing-question handling verified",
  );
}

run();
