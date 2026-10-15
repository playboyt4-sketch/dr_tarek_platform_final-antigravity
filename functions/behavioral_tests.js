const admin = require('firebase-admin');
const { initializeApp } = require('firebase/app');
const { getAuth, signInWithCustomToken } = require('firebase/auth');
const { getFirestore, doc, getDoc, setDoc } = require('firebase/firestore');
const { initializeAppCheck, CustomProvider } = require('firebase/app-check');
const fetch = require('node-fetch'); // Make sure this is installed or use built-in fetch if Node 18+

// 1. Admin setup
admin.initializeApp({ projectId: 'dr-tarek-platform' });
const adminDb = admin.firestore();
const adminAuth = admin.auth();
const adminAppCheck = admin.appCheck();

const FIREBASE_CONFIG = {
  apiKey: 'AIzaSyCCZFmVdGUd3n7hRX8vWpvWlp_t4TcUNj0',
  appId: '1:606744934510:web:0ed4cde346f56acec54e7f',
  projectId: 'dr-tarek-platform'
};

async function runTests() {
  console.log('--- Starting Behavioral Tests ---');
  const uid = 'app_check_test_user_123';
  
  // Setup isolated test data
  console.log('Setting up isolated test user...');
  await adminDb.collection('users').doc(uid).set({
    role: 'student',
    student_type: 'center_student',
    approval_status: 'approved',
    phone_number: '01000000000',
    full_name: 'App Check Test User',
    is_deleted: false
  });
  const customAuthToken = await adminAuth.createCustomToken(uid, {
    role: 'student',
    student_type: 'center_student',
    approved: true
  });
  
  // Setup a test document that the user is allowed to read by Security Rules
  await adminDb.collection('academic_periods').doc('test_period_123').set({
    status: 'active',
    is_core: true,
    is_deleted: false,
    test_marker: true
  });

  // Client SDK Setup - WITHOUT App Check
  console.log('\n--- Negative Test: Firestore Read without App Check ---');
  const appWithoutAppCheck = initializeApp(FIREBASE_CONFIG, 'no-app-check');
  const authWithoutAppCheck = getAuth(appWithoutAppCheck);
  const dbWithoutAppCheck = getFirestore(appWithoutAppCheck);
  
  await signInWithCustomToken(authWithoutAppCheck, customAuthToken);
  console.log('Signed in successfully (No App Check).');

  let negativePassed = false;
  try {
    const docRef = doc(dbWithoutAppCheck, 'academic_periods', 'test_period_123');
    await getDoc(docRef);
    console.error('❌ NEGATIVE TEST FAILED: Read succeeded without App Check!');
  } catch (err) {
    console.log('✅ NEGATIVE TEST PASSED: Read rejected.', err.code, err.message);
    negativePassed = true;
  }

  // Generate Valid App Check Token via Admin SDK
  console.log('\n--- Generating Valid App Check Token ---');
  const appCheckTokenResponse = await adminAppCheck.createToken(FIREBASE_CONFIG.appId);
  const validAppCheckToken = appCheckTokenResponse.token;
  
  // Client SDK Setup - WITH App Check
  console.log('\n--- Positive Test: Firestore Read WITH App Check ---');
  const appWithAppCheck = initializeApp(FIREBASE_CONFIG, 'with-app-check');
  
  const customProvider = new CustomProvider({
    getToken: () => {
      return Promise.resolve({
        token: validAppCheckToken,
        expireTimeMillis: Date.now() + 3600000
      });
    }
  });
  
  initializeAppCheck(appWithAppCheck, {
    provider: customProvider,
    isTokenAutoRefreshEnabled: false
  });
  
  const authWithAppCheck = getAuth(appWithAppCheck);
  const dbWithAppCheck = getFirestore(appWithAppCheck);
  await signInWithCustomToken(authWithAppCheck, customAuthToken);
  console.log('Signed in successfully (With App Check).');

  let positivePassed = false;
  try {
    const docRef = doc(dbWithAppCheck, 'academic_periods', 'test_period_123');
    const snapshot = await getDoc(docRef);
    if (snapshot.exists()) {
      console.log('✅ POSITIVE TEST PASSED: Read succeeded with valid App Check token. Document data:', snapshot.data());
      positivePassed = true;
    } else {
      console.error('❌ POSITIVE TEST FAILED: Document does not exist!');
    }
  } catch (err) {
    console.error('❌ POSITIVE TEST FAILED: Read rejected despite valid App Check token.', err.code, err.message);
  }

  // Cloud Functions Negative Test
  console.log('\n--- Negative Test: Cloud Functions without App Check ---');
  const functionUrl = 'https://us-central1-dr-tarek-platform.cloudfunctions.net/verifyPhonePassword';
  const cfResponse = await fetch(functionUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ data: { phone_number: '0100', password: '123' } })
  });
  const cfStatus = cfResponse.status;
  const cfBody = await cfResponse.text();
  
  if (cfStatus === 401 && cfBody.includes('UNAUTHENTICATED')) {
    console.log('✅ CF NEGATIVE TEST PASSED: Function rejected missing App Check token.', cfStatus);
  } else {
    console.error('❌ CF NEGATIVE TEST FAILED: Function did not reject missing App Check properly. Status:', cfStatus, 'Body:', cfBody);
  }

  // Cloud Functions Positive Test
  console.log('\\n--- Positive Test: Cloud Functions WITH App Check ---');
  const { getFunctions, httpsCallable } = require('firebase/functions');
  const functionsWithAppCheck = getFunctions(appWithAppCheck);
  const verifyPhonePassword = httpsCallable(functionsWithAppCheck, 'verifyPhonePassword');
  
  let cfPositivePassed = false;
  try {
    const result = await verifyPhonePassword({ phone_number: '01000000000', password: '123' });
    console.error('❌ CF POSITIVE TEST FAILED: Function succeeded instead of returning Invalid Argument! Result:', result.data);
  } catch (err) {
    if (err.code === 'invalid-argument') {
      console.log('✅ CF POSITIVE TEST PASSED: Function accepted App Check token and executed business logic, returning expected business error.');
      cfPositivePassed = true;
    } else {
      console.error('❌ CF POSITIVE TEST FAILED: Function returned unexpected error:', err.code, err.message);
    }
  }

  // Cleanup
  console.log('\nCleaning up test data...');
  await adminDb.collection('users').doc(uid).delete();
  await adminDb.collection('academic_periods').doc('test_period_123').delete();
  
  console.log('\n=== Summary ===');
  console.log(`Firestore Negative Test: ${negativePassed ? 'PASS' : 'FAIL'}`);
  console.log(`Firestore Positive Test: ${positivePassed ? 'PASS' : 'FAIL'}`);
}

runTests().then(() => process.exit(0)).catch(err => {
  console.error('Fatal Error:', err);
  process.exit(1);
});
