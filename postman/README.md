# Postman / Newman test toolkit

This folder helps you generate a Postman collection from your OpenAPI (Swagger) JSON and run tests locally with Newman.

Quick steps

- Install node dependencies:

```powershell
cd postman
npm install
```

- Generate the Postman collection (defaults to your local swagger URL):

```powershell
# uses https://localhost:7079/swagger/v1/swagger.json by default
npm run generate -- "https://localhost:5199/swagger/v1/swagger.json"

# Or set env var
$env:SWAGGER_URL = 'https://localhost:7079/swagger/v1/swagger.json'
npm run generate
```

- Run the collection with Newman (ignores TLS by default using `--insecure`):

```powershell
npm run run
```

## Using external test data

You can provide test data examples from an external JSON file to populate request bodies, query parameters, and headers for your endpoints.

1. Create a `test-data.json` file (see `test-data.example.json` for format):

```json
{
  "GET /api/endpoint": {
    "queryParams": {
      "id": "123"
    },
    "headers": {
      "Authorization": "Bearer TOKEN"
    }
  },
  "POST /api/endpoint": {
    "body": {
      "field": "value"
    },
    "headers": {
      "Authorization": "Bearer TOKEN"
    }
  }
}
```

2. Generate the collection with test data:

```powershell
# By default, looks for test-data.json in the postman folder
npm run generate

# Or specify a custom test data file path
npm run generate -- "https://localhost:7079/swagger/v1/swagger.json" "path/to/custom-test-data.json"

# Or use environment variable
$env:TEST_DATA_PATH = 'path/to/test-data.json'
npm run generate
```

The test data file format:
- Keys are in the format `METHOD /path` (e.g., `GET /api/users`, `POST /api/users/:id`)
- Each endpoint can specify `body`, `queryParams`, and/or `headers`
- The generator will apply these examples to matching requests in the collection

Notes and tips
- If your local dev server uses a self-signed certificate, `newman` is invoked with `--insecure` to allow requests to localhost. On Windows, you can also set `NODE_TLS_REJECT_UNAUTHORIZED=0` when needed.
- The generator attempts to replace localhost URLs in the collection with the `{{baseUrl}}` variable. You can edit `postman/dist/environment.json` to change the `baseUrl` value used by requests.
- The generator injects simple tests for each request:
  - status code is 2xx
  - response time under 5000ms
  - response is JSON (if possible)

If you want a GitHub Action to run these with Newman in CI, tell me and I can add a workflow. Note: CI cannot access `https://localhost:7079` unless your API is reachable from the runner.
