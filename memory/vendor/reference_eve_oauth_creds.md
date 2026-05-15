---
name: Eve Workspace OAuth creds reusable from Python
description: Where to find the Workspace MCP's per-user OAuth tokens so Eve's local Python scripts can call Google APIs directly without going through MCP
type: reference
originSessionId: 802209e5-5b97-40e7-9a67-a7bc40093c31
---
Workspace MCP stores per-user OAuth credentials on disk at:
`~/.google_workspace_mcp/credentials/<email>.json`

Standard `google.oauth2.credentials.Credentials.from_authorized_user_file()` format — token, refresh_token, token_uri, client_id, client_secret, scopes. Safe to load + refresh from any Python script; writing the refreshed token back keeps the MCP in sync since they share the file.

Example (`pulse_outreach.py`):
```python
from google.auth.transport.requests import Request
from google.oauth2.credentials import Credentials
creds = Credentials.from_authorized_user_file(path)
if creds.expired and creds.refresh_token:
    creds.refresh(Request())
    path.write_text(creds.to_json())
```

System `python3` (not the docs-venv) has `google-auth` + `googleapiclient` installed. docs-venv does NOT. So Python scripts that need Google APIs should run under `/usr/bin/python3`; scripts that only need feedparser/yaml/sqlite3 stdlib can use docs-venv.
