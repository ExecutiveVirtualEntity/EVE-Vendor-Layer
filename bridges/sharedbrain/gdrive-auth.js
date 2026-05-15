const { google } = require('googleapis');
const fs = require('fs');
const http = require('http');
const url = require('url');

const credentials = JSON.parse(fs.readFileSync('credentials.json'));
const { client_id, client_secret, redirect_uris } = credentials.installed;

const oauth2Client = new google.auth.OAuth2(
  client_id, client_secret, 'http://localhost:3001'
);

const authUrl = oauth2Client.generateAuthUrl({
  access_type: 'offline',
  scope: ['https://www.googleapis.com/auth/drive.readonly']
});

console.log('Opening browser for Google authentication...');
console.log('If browser does not open, visit this URL manually:');
console.log(authUrl);

const server = http.createServer(async (req, res) => {
  const code = new url.URL(req.url, 'http://localhost:3000').searchParams.get('code');
  if (code) {
    const { tokens } = await oauth2Client.getToken(code);
    fs.writeFileSync('gdrive-token.json', JSON.stringify(tokens));
    res.end('Authentication successful! You can close this window.');
    console.log('Token saved to gdrive-token.json');
    server.close();
  }
});

server.listen(3001, () => {
  const { exec } = require('child_process');
  exec(`start "" "${authUrl}"`);
});