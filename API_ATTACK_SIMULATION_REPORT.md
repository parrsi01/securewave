# API Attack Simulation Report

**Generated:** 2026-03-16T19:46:26.561881
**Target:** https://api.securewaveapp.com
**Total Tests:** 59

## Summary

| Severity | Count |
|----------|-------|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | 0 |
| LOW | 0 |
| INFO | 59 |
| **Vulnerabilities Detected** | **0** |

## Test Categories

### SQL Injection Tests
- Boolean-based blind
- Error-based
- Time-based blind
- Union-based
- NoSQL injection

### Cross-Site Scripting (XSS)
- Reflected XSS
- Stored XSS
- DOM-based XSS
- Template injection

### Command Injection
- Shell command injection
- Backtick execution
- Subshell execution

### Path Traversal
- Basic traversal
- Double encoding
- Unicode traversal
- Null byte injection

### JWT Attacks
- None algorithm
- Algorithm confusion
- Weak secrets
- Expired tokens

### Authentication Bypass
- Header spoofing
- IP bypass
- Case manipulation

## Detailed Results

### ✓ SQLi - SQLi - Quote

- **Endpoint:** `POST /api/auth/login`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `'`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body","email"],"msg":"Field required","input":{"input":"'"}},{"type":"missing","loc":["body","passw
```

---

### ✓ SQLi - SQLi - Quote

- **Endpoint:** `POST /api/auth/register`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `'`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body","email"],"msg":"Field required","input":{"input":"'"}},{"type":"missing","loc":["body","passw
```

---

### ✓ SQLi - SQLi - OR 1=1

- **Endpoint:** `POST /api/auth/login`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `' OR '1'='1`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body","email"],"msg":"Field required","input":{"input":"' OR '1'='1"}},{"type":"missing","loc":["bo
```

---

### ✓ SQLi - SQLi - OR 1=1

- **Endpoint:** `POST /api/auth/register`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `' OR '1'='1`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body","email"],"msg":"Field required","input":{"input":"' OR '1'='1"}},{"type":"missing","loc":["bo
```

---

### ✓ SQLi - SQLi - Comment

- **Endpoint:** `POST /api/auth/login`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `'--`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body","email"],"msg":"Field required","input":{"input":"'--"}},{"type":"missing","loc":["body","pas
```

---

### ✓ SQLi - SQLi - Comment

- **Endpoint:** `POST /api/auth/register`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `'--`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body","email"],"msg":"Field required","input":{"input":"'--"}},{"type":"missing","loc":["body","pas
```

---

### ✓ SQLi - SQLi - Union

- **Endpoint:** `POST /api/auth/login`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `' UNION SELECT null,null--`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body","email"],"msg":"Field required","input":{"input":"' UNION SELECT null,null--"}},{"type":"miss
```

---

### ✓ SQLi - SQLi - Union

- **Endpoint:** `POST /api/auth/register`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `' UNION SELECT null,null--`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body","email"],"msg":"Field required","input":{"input":"' UNION SELECT null,null--"}},{"type":"miss
```

---

### ✓ SQLi - SQLi - Time

- **Endpoint:** `POST /api/auth/login`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `'; SELECT pg_sleep(5)--`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body","email"],"msg":"Field required","input":{"input":"'; SELECT pg_sleep(5)--"}},{"type":"missing
```

---

### ✓ SQLi - SQLi - Time

- **Endpoint:** `POST /api/auth/register`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `'; SELECT pg_sleep(5)--`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body","email"],"msg":"Field required","input":{"input":"'; SELECT pg_sleep(5)--"}},{"type":"missing
```

---

### ✓ SQLi - SQLi - Stacked

- **Endpoint:** `POST /api/auth/login`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `'; DROP TABLE users;--`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body","email"],"msg":"Field required","input":{"input":"'; DROP TABLE users;--"}},{"type":"missing"
```

---

### ✓ SQLi - SQLi - Stacked

- **Endpoint:** `POST /api/auth/register`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `'; DROP TABLE users;--`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body","email"],"msg":"Field required","input":{"input":"'; DROP TABLE users;--"}},{"type":"missing"
```

---

### ✓ SQLi - NoSQLi - GT

- **Endpoint:** `POST /api/auth/login`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `{"$gt": ""}`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body","email"],"msg":"Field required","input":{"input":"{\"$gt\": \"\"}"}},{"type":"missing","loc":
```

---

### ✓ SQLi - NoSQLi - GT

- **Endpoint:** `POST /api/auth/register`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `{"$gt": ""}`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body","email"],"msg":"Field required","input":{"input":"{\"$gt\": \"\"}"}},{"type":"missing","loc":
```

---

### ✓ SQLi - NoSQLi - NE

- **Endpoint:** `POST /api/auth/login`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `{"$ne": null}`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body","email"],"msg":"Field required","input":{"input":"{\"$ne\": null}"}},{"type":"missing","loc":
```

---

### ✓ SQLi - NoSQLi - NE

- **Endpoint:** `POST /api/auth/register`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `{"$ne": null}`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body","email"],"msg":"Field required","input":{"input":"{\"$ne\": null}"}},{"type":"missing","loc":
```

---

### ✓ XSS - XSS - Basic

- **Endpoint:** `POST /api/auth/login`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `<script>alert('xss')</script>`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body","email"],"msg":"Field required","input":{"input":"<script>alert('xss')</script>"}},{"type":"m
```

---

### ✓ XSS - XSS - Basic

- **Endpoint:** `POST /api/auth/register`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `<script>alert('xss')</script>`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body","email"],"msg":"Field required","input":{"input":"<script>alert('xss')</script>"}},{"type":"m
```

---

### ✓ XSS - XSS - Img

- **Endpoint:** `POST /api/auth/login`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `<img src=x onerror=alert('xss')>`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body","email"],"msg":"Field required","input":{"input":"<img src=x onerror=alert('xss')>"}},{"type"
```

---

### ✓ XSS - XSS - Img

- **Endpoint:** `POST /api/auth/register`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `<img src=x onerror=alert('xss')>`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body","email"],"msg":"Field required","input":{"input":"<img src=x onerror=alert('xss')>"}},{"type"
```

---

### ✓ XSS - XSS - SVG

- **Endpoint:** `POST /api/auth/login`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `<svg onload=alert('xss')>`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body","email"],"msg":"Field required","input":{"input":"<svg onload=alert('xss')>"}},{"type":"missi
```

---

### ✓ XSS - XSS - SVG

- **Endpoint:** `POST /api/auth/register`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `<svg onload=alert('xss')>`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body","email"],"msg":"Field required","input":{"input":"<svg onload=alert('xss')>"}},{"type":"missi
```

---

### ✓ XSS - XSS - Template

- **Endpoint:** `POST /api/auth/login`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `{{7*7}}`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body","email"],"msg":"Field required","input":{"input":"{{7*7}}"}},{"type":"missing","loc":["body",
```

---

### ✓ XSS - XSS - Template

- **Endpoint:** `POST /api/auth/register`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `{{7*7}}`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body","email"],"msg":"Field required","input":{"input":"{{7*7}}"}},{"type":"missing","loc":["body",
```

---

### ✓ XSS - XSS - JS Context

- **Endpoint:** `POST /api/auth/login`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `';alert('xss');//`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body","email"],"msg":"Field required","input":{"input":"';alert('xss');//"}},{"type":"missing","loc
```

---

### ✓ XSS - XSS - JS Context

- **Endpoint:** `POST /api/auth/register`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `';alert('xss');//`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body","email"],"msg":"Field required","input":{"input":"';alert('xss');//"}},{"type":"missing","loc
```

---

### ✓ XSS - XSS - CSS

- **Endpoint:** `POST /api/auth/login`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `</style><script>alert('xss')</script>`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body","email"],"msg":"Field required","input":{"input":"</style><script>alert('xss')</script>"}},{"
```

---

### ✓ XSS - XSS - CSS

- **Endpoint:** `POST /api/auth/register`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `</style><script>alert('xss')</script>`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body","email"],"msg":"Field required","input":{"input":"</style><script>alert('xss')</script>"}},{"
```

---

### ✓ CMD - CMD - Semicolon

- **Endpoint:** `POST /api/devices`
- **Status:** 404
- **Severity:** INFO
- **Payload:** `; cat /etc/passwd`

**Response Preview:**
```
{"error":{"code":"not_found","message":"Not found","details":null},"request_id":"5bbf3c6d-3ff6-4516-bb1c-9892037eadfc"}
```

---

### ✓ CMD - CMD - Semicolon

- **Endpoint:** `GET /api/servers`
- **Status:** 404
- **Severity:** INFO
- **Payload:** `; cat /etc/passwd`

**Response Preview:**
```
{"error":{"code":"not_found","message":"Not found","details":null},"request_id":"e57ca3ac-9df3-4243-b153-dac48d278fa5"}
```

---

### ✓ CMD - CMD - Backtick

- **Endpoint:** `POST /api/devices`
- **Status:** 404
- **Severity:** INFO
- **Payload:** ``cat /etc/passwd``

**Response Preview:**
```
{"error":{"code":"not_found","message":"Not found","details":null},"request_id":"90f9bc2c-8c1b-4c39-900a-fcb22d39b52f"}
```

---

### ✓ CMD - CMD - Backtick

- **Endpoint:** `GET /api/servers`
- **Status:** 404
- **Severity:** INFO
- **Payload:** ``cat /etc/passwd``

**Response Preview:**
```
{"error":{"code":"not_found","message":"Not found","details":null},"request_id":"01a8a793-710b-47f9-896b-6cc29d15b5a5"}
```

---

### ✓ CMD - CMD - Pipe

- **Endpoint:** `POST /api/devices`
- **Status:** 404
- **Severity:** INFO
- **Payload:** `| cat /etc/passwd`

**Response Preview:**
```
{"error":{"code":"not_found","message":"Not found","details":null},"request_id":"276972ff-2c39-4b11-bfae-b8157db98f95"}
```

---

### ✓ CMD - CMD - Pipe

- **Endpoint:** `GET /api/servers`
- **Status:** 404
- **Severity:** INFO
- **Payload:** `| cat /etc/passwd`

**Response Preview:**
```
{"error":{"code":"not_found","message":"Not found","details":null},"request_id":"d01fb2ba-ac01-4d6c-9663-4f54b46a4257"}
```

---

### ✓ CMD - CMD - AND

- **Endpoint:** `POST /api/devices`
- **Status:** 404
- **Severity:** INFO
- **Payload:** `&& cat /etc/passwd`

**Response Preview:**
```
{"error":{"code":"not_found","message":"Not found","details":null},"request_id":"da0333fd-53c5-4d8a-ae36-767af4bdcf1c"}
```

---

### ✓ CMD - CMD - AND

- **Endpoint:** `GET /api/servers`
- **Status:** 404
- **Severity:** INFO
- **Payload:** `&& cat /etc/passwd`

**Response Preview:**
```
{"error":{"code":"not_found","message":"Not found","details":null},"request_id":"607deed4-4cf0-422f-b433-275e9825a1fe"}
```

---

### ✓ CMD - CMD - OR

- **Endpoint:** `POST /api/devices`
- **Status:** 404
- **Severity:** INFO
- **Payload:** `|| cat /etc/passwd`

**Response Preview:**
```
{"error":{"code":"not_found","message":"Not found","details":null},"request_id":"95b74132-d631-41e0-9c36-31ed20bbaa52"}
```

---

### ✓ CMD - CMD - OR

- **Endpoint:** `GET /api/servers`
- **Status:** 404
- **Severity:** INFO
- **Payload:** `|| cat /etc/passwd`

**Response Preview:**
```
{"error":{"code":"not_found","message":"Not found","details":null},"request_id":"ccc88e2a-9ff2-419b-9490-400ff7019e8a"}
```

---

### ✓ CMD - CMD - Subshell

- **Endpoint:** `POST /api/devices`
- **Status:** 404
- **Severity:** INFO
- **Payload:** `$(cat /etc/passwd)`

**Response Preview:**
```
{"error":{"code":"not_found","message":"Not found","details":null},"request_id":"24769876-8bc2-4865-bb56-93af027c9b07"}
```

---

### ✓ CMD - CMD - Subshell

- **Endpoint:** `GET /api/servers`
- **Status:** 404
- **Severity:** INFO
- **Payload:** `$(cat /etc/passwd)`

**Response Preview:**
```
{"error":{"code":"not_found","message":"Not found","details":null},"request_id":"8ae28fb5-b7ef-450f-8b39-0495f325a5ed"}
```

---

### ✓ CMD - CMD - Newline

- **Endpoint:** `POST /api/devices`
- **Status:** 404
- **Severity:** INFO
- **Payload:** `
cat /etc/passwd`

**Response Preview:**
```
{"error":{"code":"not_found","message":"Not found","details":null},"request_id":"428c0cac-e42a-49fa-b51a-b808638a7426"}
```

---

### ✓ CMD - CMD - Newline

- **Endpoint:** `GET /api/servers`
- **Status:** 404
- **Severity:** INFO
- **Payload:** `
cat /etc/passwd`

**Response Preview:**
```
{"error":{"code":"not_found","message":"Not found","details":null},"request_id":"51314fba-6b03-4546-b74c-27ec41445218"}
```

---

### ✓ Path - Path - Basic

- **Endpoint:** `GET /api/servers`
- **Status:** 404
- **Severity:** INFO
- **Payload:** `../../../etc/passwd`

**Response Preview:**
```
{"error":{"code":"not_found","message":"Not found","details":null},"request_id":"b4210e1e-ff06-4cf3-b928-b9e5f91e14d1"}
```

---

### ✓ Path - Path - Double

- **Endpoint:** `GET /api/servers`
- **Status:** 404
- **Severity:** INFO
- **Payload:** `....//....//....//etc/passwd`

**Response Preview:**
```
{"error":{"code":"not_found","message":"Not found","details":null},"request_id":"f17eb34a-e237-4fe8-8676-3f1c028f73a5"}
```

---

### ✓ Path - Path - URL Encoded

- **Endpoint:** `GET /api/servers`
- **Status:** 404
- **Severity:** INFO
- **Payload:** `%2e%2e%2f%2e%2e%2f%2e%2e%2fetc%2fpasswd`

**Response Preview:**
```
{"error":{"code":"not_found","message":"Not found","details":null},"request_id":"a098fb39-2c2c-460b-bf0b-3a06b0476d88"}
```

---

### ✓ Path - Path - Null Byte

- **Endpoint:** `GET /api/servers`
- **Status:** 404
- **Severity:** INFO
- **Payload:** `../../../etc/passwd%00`

**Response Preview:**
```
{"error":{"code":"not_found","message":"Not found","details":null},"request_id":"61e1d814-dc2f-4034-a8c7-2e0852b1d2d4"}
```

---

### ✓ Path - Path - Unicode

- **Endpoint:** `GET /api/servers`
- **Status:** 404
- **Severity:** INFO
- **Payload:** `..%c0%af..%c0%af..%c0%afetc/passwd`

**Response Preview:**
```
{"error":{"code":"not_found","message":"Not found","details":null},"request_id":"92646e44-ada8-4a13-941b-765ec53d5ddf"}
```

---

### ✓ JWT - JWT None Algorithm

- **Endpoint:** `POST /api/devices`
- **Status:** 404
- **Severity:** INFO
- **Payload:** `eyJhbGciOiAibm9uZSIsICJ0eXAiOiAiSldUIn0.eyJzdWIiOiAiYWRtaW4iLCAicm9sZSI6ICJhZG1pbiJ9.`

**Response Preview:**
```
{"error":{"code":"not_found","message":"Not found","details":null},"request_id":"b21173c6-5f47-40d0-bf86-04cded45876f"}
```

---

### ✓ JWT - JWT None Algorithm

- **Endpoint:** `GET /api/servers`
- **Status:** 404
- **Severity:** INFO
- **Payload:** `eyJhbGciOiAibm9uZSIsICJ0eXAiOiAiSldUIn0.eyJzdWIiOiAiYWRtaW4iLCAicm9sZSI6ICJhZG1pbiJ9.`

**Response Preview:**
```
{"error":{"code":"not_found","message":"Not found","details":null},"request_id":"dab9b004-f733-4e7d-aa34-01812d6a19b9"}
```

---

### ✓ JWT - JWT Algorithm Confusion

- **Endpoint:** `POST /api/devices`
- **Status:** 404
- **Severity:** INFO
- **Payload:** `eyJhbGciOiAiSFMyNTYiLCAidHlwIjogIkpXVCJ9.eyJzdWIiOiAiYWRtaW4iLCAicm9sZSI6ICJhZG1pbiJ9.fake_signature`

**Response Preview:**
```
{"error":{"code":"not_found","message":"Not found","details":null},"request_id":"2e17510c-f4a8-423c-80d9-7429e4b16366"}
```

---

### ✓ JWT - JWT Algorithm Confusion

- **Endpoint:** `GET /api/servers`
- **Status:** 404
- **Severity:** INFO
- **Payload:** `eyJhbGciOiAiSFMyNTYiLCAidHlwIjogIkpXVCJ9.eyJzdWIiOiAiYWRtaW4iLCAicm9sZSI6ICJhZG1pbiJ9.fake_signature`

**Response Preview:**
```
{"error":{"code":"not_found","message":"Not found","details":null},"request_id":"96f6d21e-472b-488c-845f-b71f618cf9b7"}
```

---

### ✓ JWT - JWT Expired Token

- **Endpoint:** `POST /api/devices`
- **Status:** 404
- **Severity:** INFO
- **Payload:** `eyJhbGciOiAiSFMyNTYiLCAidHlwIjogIkpXVCJ9.eyJzdWIiOiAiMSIsICJleHAiOiAwfQ.signature`

**Response Preview:**
```
{"error":{"code":"not_found","message":"Not found","details":null},"request_id":"e59d2aa5-5972-4222-b50d-2a7edce0f2a8"}
```

---

### ✓ JWT - JWT Expired Token

- **Endpoint:** `GET /api/servers`
- **Status:** 404
- **Severity:** INFO
- **Payload:** `eyJhbGciOiAiSFMyNTYiLCAidHlwIjogIkpXVCJ9.eyJzdWIiOiAiMSIsICJleHAiOiAwfQ.signature`

**Response Preview:**
```
{"error":{"code":"not_found","message":"Not found","details":null},"request_id":"71b267dc-7caf-44c8-bd34-545ba02cd436"}
```

---

### ✓ JWT - JWT Empty Signature

- **Endpoint:** `POST /api/devices`
- **Status:** 404
- **Severity:** INFO
- **Payload:** `eyJhbGciOiAiSFMyNTYiLCAidHlwIjogIkpXVCJ9.eyJzdWIiOiAiYWRtaW4iLCAicm9sZSI6ICJhZG1pbiJ9.`

**Response Preview:**
```
{"error":{"code":"not_found","message":"Not found","details":null},"request_id":"da4fa68c-bc27-4f26-a23b-e93fd04ccc9d"}
```

---

### ✓ JWT - JWT Empty Signature

- **Endpoint:** `GET /api/servers`
- **Status:** 404
- **Severity:** INFO
- **Payload:** `eyJhbGciOiAiSFMyNTYiLCAidHlwIjogIkpXVCJ9.eyJzdWIiOiAiYWRtaW4iLCAicm9sZSI6ICJhZG1pbiJ9.`

**Response Preview:**
```
{"error":{"code":"not_found","message":"Not found","details":null},"request_id":"17f5a441-9795-49ac-be78-be07cff510ed"}
```

---

### ✓ Rate - Rate - XFF

- **Endpoint:** `POST /api/auth/login`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `{'name': 'Rate - XFF', 'headers': {'X-Forwarded-For': '1.2.3.4'}, 'type': 'header'}`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body"],"msg":"Field required","input":null}]},"request_id":"4a7b89bd-3cfc-434d-817c-264965248aea"}
```

---

### ✓ Rate - Rate - CF

- **Endpoint:** `POST /api/auth/login`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `{'name': 'Rate - CF', 'headers': {'CF-Connecting-IP': '1.2.3.4'}, 'type': 'header'}`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body"],"msg":"Field required","input":null}]},"request_id":"56e3ed57-1b03-4f26-b624-d31dfe150b4f"}
```

---

### ✓ Rate - Rate - XRI

- **Endpoint:** `POST /api/auth/login`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `{'name': 'Rate - XRI', 'headers': {'X-Real-IP': '1.2.3.4'}, 'type': 'header'}`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body"],"msg":"Field required","input":null}]},"request_id":"f981433c-f123-4338-8da9-e78ff391e16e"}
```

---

### ✓ Rate - Rate - XCIP

- **Endpoint:** `POST /api/auth/login`
- **Status:** 422
- **Severity:** INFO
- **Payload:** `{'name': 'Rate - XCIP', 'headers': {'X-Client-IP': '1.2.3.4'}, 'type': 'header'}`

**Response Preview:**
```
{"error":{"code":"validation_error","message":"Invalid request","details":[{"type":"missing","loc":["body"],"msg":"Field required","input":null}]},"request_id":"a9685d36-c9bd-4412-bdc3-88335f9dfa68"}
```

---

## Recommendations

### Immediate Actions
1. Implement parameterized queries for all database operations
2. Sanitize all user input before rendering in responses
3. Validate JWT signatures with strong algorithms
4. Implement rate limiting with proper IP validation
5. Use path canonicalization before file access

### Defense Layers
- Web Application Firewall (WAF)
- Input validation and sanitization
- Output encoding
- Principle of least privilege
- Security headers (CSP, X-Frame-Options, etc.)

