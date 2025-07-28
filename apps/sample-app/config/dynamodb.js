const AWS = require('aws-sdk');

// Configure AWS
const config = {
  region: process.env.AWS_REGION || 'us-east-1',
  accessKeyId: process.env.AWS_ACCESS_KEY_ID,
  secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY
};

// Add LocalStack endpoint for development
if (process.env.DYNAMODB_ENDPOINT) {
  config.endpoint = process.env.DYNAMODB_ENDPOINT;
}

AWS.config.update(config);

// Create DynamoDB client
const dynamodb = new AWS.DynamoDB();
const docClient = new AWS.DynamoDB.DocumentClient();

// Table configuration
const TABLE_NAME = process.env.DYNAMODB_TABLE_NAME || 'sample-app-items';

module.exports = {
  dynamodb,
  docClient,
  TABLE_NAME
};