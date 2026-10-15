const { GoogleAuth } = require('google-auth-library');

async function checkAppCheck() {
  try {
    const auth = new GoogleAuth({
      scopes: 'https://www.googleapis.com/auth/cloud-platform'
    });
    const client = await auth.getClient();
    const projectId = 'dr-tarek-platform';
    const url = `https://firebaseappcheck.googleapis.com/v1/projects/${projectId}/services/firestore.googleapis.com`;
    const res = await client.request({ url });
    console.log("SUCCESS:", JSON.stringify(res.data, null, 2));
  } catch (err) {
    console.error("ERROR:", err.message);
    if (err.response) {
      console.error(JSON.stringify(err.response.data, null, 2));
    }
  }
}
checkAppCheck();
