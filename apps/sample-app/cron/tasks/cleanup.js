const { docClient, TABLE_NAME } = require('../../config/dynamodb');

async function cleanupOldRecords() {
  console.log('🧹 Starting cleanup of old records...');
  
  try {
    // Calculate cutoff date (30 days ago)
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - 30);
    const cutoffISO = cutoffDate.toISOString();

    // Scan for old records
    const scanParams = {
      TableName: TABLE_NAME,
      FilterExpression: 'createdAt < :cutoffDate',
      ExpressionAttributeValues: {
        ':cutoffDate': cutoffISO
      }
    };

    const scanResult = await docClient.scan(scanParams).promise();
    const oldItems = scanResult.Items;

    if (oldItems.length === 0) {
      console.log('No old records found for cleanup');
      return { deleted: 0 };
    }

    console.log(`Found ${oldItems.length} old records to delete`);

    // Delete old items in batches
    const batchSize = 25; // DynamoDB batch limit
    let deletedCount = 0;

    for (let i = 0; i < oldItems.length; i += batchSize) {
      const batch = oldItems.slice(i, i + batchSize);
      
      const deleteRequests = batch.map(item => ({
        DeleteRequest: {
          Key: { id: item.id }
        }
      }));

      const batchParams = {
        RequestItems: {
          [TABLE_NAME]: deleteRequests
        }
      };

      await docClient.batchWrite(batchParams).promise();
      deletedCount += batch.length;
      
      console.log(`Deleted batch ${Math.floor(i / batchSize) + 1}, total deleted: ${deletedCount}`);
    }

    console.log(`✅ Cleanup completed. Deleted ${deletedCount} old records`);
    return { deleted: deletedCount };

  } catch (error) {
    console.error('❌ Cleanup failed:', error);
    throw error;
  }
}

module.exports = { cleanupOldRecords };