# OpenAPI to Postman/Newman Test Generator

## Overview

This tool converts an OpenAPI/Swagger JSON definition into a Postman collection with automated tests for all endpoints. It supports loading test data from an external JSON file to populate request examples.

## Features

- ✅ Converts OpenAPI/Swagger to Postman collection
- ✅ Generates Newman-compatible test files
- ✅ Automatic test generation for all endpoints (status codes, response times, JSON validation)
- ✅ External test data file support for request bodies, query parameters, and headers
- ✅ Supports both local and remote OpenAPI definitions
- ✅ Automatic URL variable replacement for flexibility

## Quick Start

### 1. Install Dependencies

```powershell
cd postman
npm install
```

### 2. Basic Usage (No Test Data)

Generate a collection from your API's OpenAPI definition:

```powershell
npm run generate -- "https://localhost:7079/swagger/v1/swagger.json"
```

### 3. Run Tests with Newman

```powershell
npm run run
```

## Using External Test Data

### Step 1: Create Test Data File

Create a `test-data.json` file with example data for your endpoints:

```json
{
  "GET /api/users": {
    "queryParams": {
      "page": "1",
      "limit": "10"
    },
    "headers": {
      "Authorization": "Bearer YOUR_TOKEN"
    }
  },
  "POST /api/users": {
    "body": {
      "username": "testuser",
      "email": "test@example.com",
      "password": "SecurePass123!"
    },
    "headers": {
      "Authorization": "Bearer YOUR_TOKEN"
    }
  },
  "PUT /api/users/:id": {
    "body": {
      "username": "updateduser",
      "email": "updated@example.com"
    }
  },
  "DELETE /api/users/:id": {
    "headers": {
      "Authorization": "Bearer YOUR_TOKEN"
    }
  }
}
```

### Step 2: Generate Collection with Test Data

```powershell
# Using default test-data.json location (postman folder)
npm run generate

# Using custom test data file
npm run generate -- "https://localhost:7079/swagger/v1/swagger.json" "path\to\custom-test-data.json"

# Using environment variables
$env:SWAGGER_URL = 'https://localhost:7079/swagger/v1/swagger.json'
$env:TEST_DATA_PATH = 'path\to\test-data.json'
npm run generate
```

## Test Data File Format

### Structure

The test data file is a JSON object where:
- **Keys** are in the format: `METHOD /path` (e.g., `GET /api/users`, `POST /api/orders/:id`)
- **Values** are objects containing optional `body`, `queryParams`, and/or `headers`

### Example Entry

```json
{
  "POST /api/products": {
    "body": {
      "name": "Test Product",
      "price": 29.99,
      "category": "electronics",
      "inStock": true
    },
    "queryParams": {
      "validate": "true"
    },
    "headers": {
      "Authorization": "Bearer YOUR_API_TOKEN",
      "X-Custom-Header": "custom-value"
    }
  }
}
```

### Field Descriptions

- **`body`**: JSON object to use as the request body (for POST, PUT, PATCH requests)
- **`queryParams`**: Key-value pairs for URL query parameters
- **`headers`**: Key-value pairs for HTTP headers

## Configuration Options

### Environment Variables

- `SWAGGER_URL`: URL to your OpenAPI/Swagger JSON (default: `https://localhost:7079/swagger/v1/swagger.json`)
- `TEST_DATA_PATH`: Path to test data file (default: `postman/test-data.json`)
- `BASE_URL`: Base URL for API requests (default: extracted from OpenAPI servers)

### Command Line Arguments

```powershell
npm run generate -- [SWAGGER_URL] [TEST_DATA_PATH]
```

Examples:
```powershell
# Just Swagger URL
npm run generate -- "https://api.example.com/swagger.json"

# Swagger URL + Test Data Path
npm run generate -- "https://localhost:7079/swagger/v1/swagger.json" "my-test-data.json"
```

## Generated Files

The tool generates two files in the `postman/dist` folder:

1. **`collection.json`**: The Postman collection with all endpoints and tests
2. **`environment.json`**: The environment file with variables (e.g., `baseUrl`)

## Automatic Tests

Every endpoint automatically gets these tests:

1. **Status Code Check**: Validates response is 2xx
2. **Response Time**: Ensures response is under 5000ms
3. **JSON Validation**: Verifies response is valid JSON (if Content-Type indicates JSON)

## Advanced Usage

### Self-Signed Certificates

The Newman runner uses `--insecure` by default for local development with self-signed certificates.

### Custom Environment Variables

Edit `postman/dist/environment.json` after generation to customize variables:

```json
{
  "id": "env-jiraxray",
  "name": "JiraXrayLocal",
  "values": [
    {
      "key": "baseUrl",
      "value": "https://localhost:7079",
      "enabled": true
    },
    {
      "key": "apiToken",
      "value": "your-token-here",
      "enabled": true
    }
  ]
}
```

Then use variables in test data:
```json
{
  "GET /api/users": {
    "headers": {
      "Authorization": "Bearer {{apiToken}}"
    }
  }
}
```

### Running Specific Folders/Requests

```powershell
# Run specific folder
npx newman run .\dist\collection.json -e .\dist\environment.json --folder "Users" --insecure

# Run with iterations
npx newman run .\dist\collection.json -e .\dist\environment.json --iteration-count 5 --insecure
```

## Troubleshooting

### Issue: "Failed to fetch" error

**Solution**: Ensure your API is running and the Swagger URL is accessible. For HTTPS with self-signed certs, the fetch might fail; consider using HTTP during development or properly configure SSL.

### Issue: Test data not applied

**Solution**: 
- Verify the endpoint key format matches exactly: `METHOD /path`
- Check that paths match your OpenAPI definition (including path parameters like `:id`)
- Look at the generated `collection.json` to see the actual path structure

### Issue: Newman fails with SSL errors

**Solution**: The `--insecure` flag is already included in the npm run script. If issues persist, set:
```powershell
$env:NODE_TLS_REJECT_UNAUTHORIZED = '0'
npm run run
```

## Examples

See `test-data.example.json` for a complete example file structure.

## Integration with CI/CD

The generated collection can be run in CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
- name: Run API Tests
  run: |
    cd postman
    npm install
    npm run generate -- "${{ secrets.API_URL }}/swagger.json"
    npm run run
```

## Support

For issues or questions, refer to the main project README or check the Postman/Newman documentation:
- [Postman Collection SDK](https://www.postmanlabs.com/)
- [Newman Documentation](https://github.com/postmanlabs/newman)
