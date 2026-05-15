const { google } = require('googleapis');
const fs = require('fs');
const readline = require('readline');

const credentials = JSON.parse(fs.readFileSync('credentials.json'));
const token = JSON.parse(fs.readFileSync('gdrive-token.json'));
const { client_id, client_secret } = credentials.installed;

const oauth2Client = new google.auth.OAuth2(client_id, client_secret, 'http://localhost:3001');
oauth2Client.setCredentials(token);

const drive = google.drive({ version: 'v3', auth: oauth2Client });

// MCP protocol over stdio
process.stdin.setEncoding('utf8');
const rl = readline.createInterface({ input: process.stdin });

function send(obj) {
  process.stdout.write(JSON.stringify(obj) + '\n');
}

rl.on('line', async (line) => {
  try {
    const msg = JSON.parse(line);

    if (msg.method === 'initialize') {
      send({ jsonrpc: '2.0', id: msg.id, result: {
        protocolVersion: '2024-11-05',
        capabilities: { tools: {} },
        serverInfo: { name: 'gdrive', version: '1.0.0' }
      }});
    }

    else if (msg.method === 'tools/list') {
      send({ jsonrpc: '2.0', id: msg.id, result: { tools: [
        { name: 'search_files', description: 'Search for files in Google Drive',
          inputSchema: { type: 'object', properties: { query: { type: 'string' } }, required: ['query'] } },
        { name: 'read_file', description: 'Read content of a Google Doc or text file',
          inputSchema: { type: 'object', properties: { fileId: { type: 'string' } }, required: ['fileId'] } },
        { name: 'list_files', description: 'List files in Google Drive',
          inputSchema: { type: 'object', properties: { folder: { type: 'string' } } } }
      ]}});
    }

    else if (msg.method === 'tools/call') {
      const { name, arguments: args } = msg.params;

      if (name === 'search_files') {
        const res = await drive.files.list({
          q: `name contains '${args.query}'`,
          fields: 'files(id, name, mimeType, modifiedTime)',
          pageSize: 20
        });
        send({ jsonrpc: '2.0', id: msg.id, result: {
          content: [{ type: 'text', text: JSON.stringify(res.data.files, null, 2) }]
        }});
      }

      else if (name === 'list_files') {
        const q = args.folder ? `'${args.folder}' in parents` : undefined;
        const res = await drive.files.list({
          q, fields: 'files(id, name, mimeType, modifiedTime)', pageSize: 50
        });
        send({ jsonrpc: '2.0', id: msg.id, result: {
          content: [{ type: 'text', text: JSON.stringify(res.data.files, null, 2) }]
        }});
      }

      else if (name === 'read_file') {
        const meta = await drive.files.get({ fileId: args.fileId, fields: 'mimeType, name' });
        let text;
        if (meta.data.mimeType === 'application/vnd.google-apps.document') {
          const res = await drive.files.export({ fileId: args.fileId, mimeType: 'text/plain' });
          text = res.data;
        } else {
          const res = await drive.files.get({ fileId: args.fileId, alt: 'media' }, { responseType: 'text' });
          text = res.data;
        }
        send({ jsonrpc: '2.0', id: msg.id, result: {
          content: [{ type: 'text', text: String(text) }]
        }});
      }
    }

    else if (msg.method === 'notifications/initialized') {
      // ignore
    }

    else {
      send({ jsonrpc: '2.0', id: msg.id, result: {} });
    }

  } catch (e) {
    send({ jsonrpc: '2.0', id: msg?.id, error: { code: -32603, message: e.message } });
  }
});