const fs = require('fs');
const path = require('path');
const fetch = require('node-fetch');
const converter = require('openapi-to-postmanv2');

async function fetchSwagger(url) {
  console.log(`Fetching OpenAPI from ${url}`);
  const res = await fetch(url, { timeout: 20000 });
  if (!res.ok) throw new Error(`Failed to fetch ${url}: ${res.status} ${res.statusText}`);
  return res.json();
}

function writeFileSyncRecursive(filePath, content) {
  const dir = path.dirname(filePath);
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(filePath, content, 'utf8');
}

function loadTestData(testDataPath) {
  if (!testDataPath || !fs.existsSync(testDataPath)) {
    return null;
  }
  try {
    const content = fs.readFileSync(testDataPath, 'utf8');
    const data = JSON.parse(content);
    console.log(`Loaded test data from ${testDataPath}`);
    return data;
  } catch (e) {
    console.warn(`Failed to load test data from ${testDataPath}:`, e.message);
    return null;
  }
}

function getRequestKey(item) {
  if (!item.request) return null;
  const method = item.request.method || 'GET';
  const url = item.request.url;
  let path = '';
  if (typeof url === 'string') {
    path = url.replace(/{{baseUrl}}/g, '').replace(/https?:\/\/[^\/]+/g, '');
  } else if (url && url.path) {
    path = Array.isArray(url.path) ? '/' + url.path.join('/') : url.path;
  }
  return `${method} ${path}`;
}

function applyTestDataToItem(item, testData) {
  if (!item.request || !testData) return;
  
  const key = getRequestKey(item);
  if (!key || !testData[key]) return;
  
  const data = testData[key];
  
  // Apply body example if provided
  if (data.body && item.request.body) {
    item.request.body.raw = JSON.stringify(data.body, null, 2);
    if (!item.request.body.options) item.request.body.options = {};
    if (!item.request.body.options.raw) item.request.body.options.raw = {};
    item.request.body.options.raw.language = 'json';
  }
  
  // Apply query parameters if provided
  if (data.queryParams && item.request.url) {
    if (typeof item.request.url === 'object') {
      item.request.url.query = item.request.url.query || [];
      Object.entries(data.queryParams).forEach(([key, value]) => {
        const existing = item.request.url.query.find(q => q.key === key);
        if (existing) {
          existing.value = value;
        } else {
          item.request.url.query.push({ key, value, disabled: false });
        }
      });
    }
  }
  
  // Apply headers if provided
  if (data.headers && item.request.header) {
    Object.entries(data.headers).forEach(([key, value]) => {
      const existing = item.request.header.find(h => h.key.toLowerCase() === key.toLowerCase());
      if (existing) {
        existing.value = value;
      } else {
        item.request.header.push({ key, value, disabled: false });
      }
    });
  }
}

function addTestsToItem(item, testData) {
  if (item.request) {
    const testScript = `pm.test("Status code is 2xx", function () { pm.expect(pm.response.code).to.be.within(200, 299); });\n` +
      `pm.test("Response time is acceptable", function () { pm.expect(pm.response.responseTime).to.be.below(5000); });\n` +
      `try { pm.test("Response is JSON", function () { pm.response.to.have.header('Content-Type'); var ct = pm.response.headers.get('Content-Type') || pm.response.headers.get('content-type'); pm.expect(ct).to.include('application/json'); pm.response.json(); }); } catch(e) { /* non-json or no body */ }`;

    item.event = item.event || [];
    const hasTest = item.event.some(e => e.listen === 'test' && e.script && e.script.exec && e.script.exec.join('\n').includes('Status code is 2xx'));
    if (!hasTest) {
      item.event.push({
        listen: 'test',
        script: {
          type: 'text/javascript',
          exec: testScript.split('\n')
        }
      });
    }
    
    // Apply test data examples
    applyTestDataToItem(item, testData);
  }
  if (item.item && Array.isArray(item.item)) {
    item.item.forEach(i => addTestsToItem(i, testData));
  }
}

function addTestsToCollection(collection, testData) {
  if (collection.item && Array.isArray(collection.item)) {
    collection.item.forEach(i => addTestsToItem(i, testData));
  }
}

async function main() {
  const swaggerUrl = process.argv[2] || process.env.SWAGGER_URL || 'https://localhost:7079/swagger/v1/swagger.json';
  const testDataPath = process.argv[3] || process.env.TEST_DATA_PATH || path.join(__dirname, 'test-data.json');
  
  try {
    const swagger = await fetchSwagger(swaggerUrl);
    const testData = loadTestData(testDataPath);

    converter.convert({ type: 'json', data: swagger }, {}, (err, result) => {
      if (err) {
        console.error('Conversion error', err);
        process.exit(1);
      }
      if (!result.result) {
        console.error('Conversion failed:', result.reason);
        process.exit(1);
      }

      const collection = result.output[0].data;

      const baseUrl = process.env.BASE_URL || (swagger.servers && swagger.servers[0] && swagger.servers[0].url) || 'https://localhost:7079';

      const environment = {
        id: 'env-jiraxray',
        name: 'JiraXrayLocal',
        values: [
          { key: 'baseUrl', value: baseUrl, enabled: true }
        ]
      };

      function replaceUrls(obj) {
        if (!obj) return;
        if (typeof obj === 'string') return obj.replace(/https?:\/\/localhost(:\d+)?/g, '{{baseUrl}}');
        if (Array.isArray(obj)) return obj.map(replaceUrls);
        if (typeof obj === 'object') {
          Object.keys(obj).forEach(k => { obj[k] = replaceUrls(obj[k]); });
          return obj;
        }
        return obj;
      }

      replaceUrls(collection);

      addTestsToCollection(collection, testData);

      const outDir = path.join(__dirname, 'dist');
      writeFileSyncRecursive(path.join(outDir, 'collection.json'), JSON.stringify(collection, null, 2));
      writeFileSyncRecursive(path.join(outDir, 'environment.json'), JSON.stringify(environment, null, 2));

      console.log('Collection written to', path.join(outDir, 'collection.json'));
      console.log('Environment written to', path.join(outDir, 'environment.json'));
      console.log('Run tests:');
      console.log('  npm run run');
    });
  } catch (e) {
    console.error('Error:', e.message || e);
    process.exit(1);
  }
}
main();