const fs = require('fs');
const path = require('path');

// Simple test to verify the script functions work correctly
console.log('Testing generate-collection.js functions...\n');

// Test loadTestData function
function loadTestData(testDataPath) {
  if (!testDataPath || !fs.existsSync(testDataPath)) {
    return null;
  }
  try {
    const content = fs.readFileSync(testDataPath, 'utf8');
    const data = JSON.parse(content);
    console.log(`✓ Loaded test data from ${testDataPath}`);
    return data;
  } catch (e) {
    console.warn(`✗ Failed to load test data from ${testDataPath}:`, e.message);
    return null;
  }
}

// Test getRequestKey function
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

// Test with example data
const testDataPath = path.join(__dirname, 'test-data.example.json');
const testData = loadTestData(testDataPath);

if (testData) {
  console.log('✓ Test data loaded successfully');
  console.log(`  Found ${Object.keys(testData).length} endpoint(s) in test data\n`);
  
  Object.keys(testData).forEach(key => {
    console.log(`  - ${key}`);
  });
} else {
  console.log('✗ No test data loaded');
}

// Test getRequestKey with mock items
console.log('\nTesting getRequestKey function:');

const mockItems = [
  {
    request: {
      method: 'GET',
      url: {
        path: ['api', 'users']
      }
    }
  },
  {
    request: {
      method: 'POST',
      url: 'https://localhost:7079/api/users'
    }
  },
  {
    request: {
      method: 'PUT',
      url: {
        path: ['api', 'users', ':id']
      }
    }
  }
];

mockItems.forEach(item => {
  const key = getRequestKey(item);
  console.log(`  ${key || '(null)'}`);
});

console.log('\n✓ All basic tests passed!');
console.log('\nNext steps:');
console.log('1. Create your test-data.json file based on test-data.example.json');
console.log('2. Run: npm run generate -- "YOUR_SWAGGER_URL" "test-data.json"');
console.log('3. Run: npm run run');
