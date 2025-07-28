#!/bin/bash

# Create DynamoDB table for sample app

TABLE_NAME="sample-app-items"
REGION="us-east-1"

echo "Creating DynamoDB table: $TABLE_NAME"

aws dynamodb create-table \
    --table-name $TABLE_NAME \
    --attribute-definitions \
        AttributeName=id,AttributeType=S \
    --key-schema \
        AttributeName=id,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region $REGION

echo "Waiting for table to be created..."
aws dynamodb wait table-exists --table-name $TABLE_NAME --region $REGION

echo "Table created successfully!"
echo "Table ARN:"
aws dynamodb describe-table --table-name $TABLE_NAME --region $REGION --query 'Table.TableArn' --output text