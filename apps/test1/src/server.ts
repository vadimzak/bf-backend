import express from 'express';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, ScanCommand } from '@aws-sdk/lib-dynamodb';

const app = express();
const PORT = process.env.PORT || 3000;

const dynamoClient = new DynamoDBClient({
  region: process.env.AWS_REGION || 'il-central-1'
});
const docClient = DynamoDBDocumentClient.from(dynamoClient);

const TABLE_NAME = 'test1-items';

app.use(express.static('public'));

app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

app.get('/api/items', async (req, res) => {
  try {
    const command = new ScanCommand({
      TableName: TABLE_NAME
    });
    
    const result = await docClient.send(command);
    res.json({
      items: result.Items || [],
      count: result.Count || 0
    });
  } catch (error) {
    console.error('Error scanning table:', error);
    res.status(500).json({ 
      error: 'Failed to scan table',
      message: error instanceof Error ? error.message : 'Unknown error'
    });
  }
});

app.get('/', (req, res) => {
  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
        <title>Test1 App</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 40px; }
            .container { max-width: 600px; }
            button { padding: 10px 20px; margin: 10px 0; }
            .items { margin-top: 20px; padding: 20px; background: #f5f5f5; }
        </style>
    </head>
    <body>
        <div class="container">
            <h1>Test1 App</h1>
            <p>Simple test application for deployment verification.</p>
            
            <button onclick="loadItems()">Load Items from DynamoDB</button>
            
            <div id="items" class="items" style="display: none;">
                <h3>Items:</h3>
                <div id="itemsList"></div>
            </div>
        </div>
        
        <script>
            async function loadItems() {
                try {
                    const response = await fetch('/api/items');
                    const data = await response.json();
                    
                    const itemsDiv = document.getElementById('items');
                    const itemsList = document.getElementById('itemsList');
                    
                    if (data.error) {
                        itemsList.innerHTML = '<p style="color: red;">Error: ' + data.error + '</p>';
                    } else {
                        itemsList.innerHTML = '<p>Count: ' + data.count + '</p><pre>' + JSON.stringify(data.items, null, 2) + '</pre>';
                    }
                    
                    itemsDiv.style.display = 'block';
                } catch (error) {
                    console.error('Error:', error);
                    alert('Failed to load items');
                }
            }
        </script>
    </body>
    </html>
  `);
});

app.listen(PORT, () => {
  console.log(`Test1 server running on port ${PORT}`);
});