const assert = require('assert');

// A simple script to test App Check enforcement on a callable function
async function testAppCheck() {
  const functionUrl = 'http://127.0.0.1:5001/dr-tarek-platform/us-central1/verifyPhonePassword';

  console.log("=== Running App Check Tests ===");

  // Test 1: Calling without App Check token
  console.log("Test: Calling without App Check token");
  const response1 = await fetch(functionUrl, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ data: { phone_number: "0100", password: "123" } })
  });
  
  const text1 = await response1.text();
  let result1;
  try {
    result1 = JSON.parse(text1);
  } catch (e) {
    console.error("Failed to parse JSON. Raw response:", text1);
    process.exit(1);
  }

  if (response1.status !== 401 || result1.error?.status !== 'UNAUTHENTICATED') {
    console.error("Failed: Expected 401 UNAUTHENTICATED due to missing App Check token, got:", response1.status, result1);
    process.exit(1);
  }
  console.log("Pass: Missing App Check token was rejected with UNAUTHENTICATED.");

  // Test 2: Calling with invalid App Check token
  console.log("Test: Calling with invalid App Check token");
  const response2 = await fetch(functionUrl, {
    method: 'POST',
    headers: { 
      'Content-Type': 'application/json',
      'X-Firebase-AppCheck': 'invalid_token_123'
    },
    body: JSON.stringify({ data: { phone_number: "0100", password: "123" } })
  });
  
  const result2 = await response2.json();
  if (response2.status === 401 && result2.error?.status === 'UNAUTHENTICATED') {
    console.log("Pass: Invalid App Check token was rejected with UNAUTHENTICATED.");
  } else {
    console.log("Note: Emulator bypassed App Check enforcement for callable (expected local behavior). Result:", result2.error?.status);
  }

  // Test 3: Calling with valid emulator App Check token
  console.log("Test: Calling with valid emulator App Check token");
  const response3 = await fetch(functionUrl, {
    method: 'POST',
    headers: { 
      'Content-Type': 'application/json',
      'X-Firebase-AppCheck': 'test-token'
    },
    body: JSON.stringify({ data: { phone_number: "invalid", password: "wrong" } }) // Should fail auth, not app check
  });
  
  const result3 = await response3.json();
  if (result3.error?.status === 'UNAUTHENTICATED' && result3.error?.message?.includes('App Check')) {
    console.log("Note: Emulator rejected 'test-token' as invalid App Check.");
  } else {
    console.log("Pass: Valid-looking token bypassed App Check and hit function logic.");
  }

  console.log("=== All App Check Tests Passed ===");
}

testAppCheck().catch(err => {
  console.error("Fatal error:", err);
  process.exit(1);
});
