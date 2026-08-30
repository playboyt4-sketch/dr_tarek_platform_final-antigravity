const { readFileSync } = require('fs');
const { initializeTestEnvironment, assertSucceeds, assertFails } = require('@firebase/rules-unit-testing');

async function run() {
  const testEnv = await initializeTestEnvironment({
    projectId: 'dr-tarek-platform-emulator',
    firestore: {
      rules: readFileSync('d:/antigravity/dr_tarek_platform_final/firestore.rules', 'utf8'),
      host: '127.0.0.1',
      port: 8080
    }
  });

  const teacherDb = testEnv.authenticatedContext('teacher-1', {role: 'teacher', approved: true}).firestore();
  
  await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().collection('lectures').doc('lec-student-vis').set({
        subject_id: 'subject-1',
        section_id: 'sec-custom',
        title: 'Draft',
        description: 'Testing',
        display_order: 1,
        publish_date: new Date(),
        status: 'published',
        is_deleted: false,
      });
  });

  const unsubscribedStudent = testEnv.authenticatedContext('student-unsub', {role: 'student', approved: true}).firestore();
  
  console.log("Checking get...");
  try {
    await unsubscribedStudent.collection('lectures').doc('lec-student-vis').get();
    console.log("SUCCESS!");
  } catch(e) {
    console.log("ERROR!");
    console.log(e);
  }

  await testEnv.cleanup();
}

run();
