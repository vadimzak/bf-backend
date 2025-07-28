const { docClient, TABLE_NAME } = require('../../config/dynamodb');

async function generateReports() {
  console.log('📊 Starting weekly report generation...');
  
  try {
    // Get all items from last week
    const oneWeekAgo = new Date();
    oneWeekAgo.setDate(oneWeekAgo.getDate() - 7);
    const weekStartISO = oneWeekAgo.toISOString();

    const scanParams = {
      TableName: TABLE_NAME,
      FilterExpression: 'createdAt >= :weekStart',
      ExpressionAttributeValues: {
        ':weekStart': weekStartISO
      }
    };

    const result = await docClient.scan(scanParams).promise();
    const weeklyItems = result.Items;

    // Generate basic statistics
    const stats = {
      totalItems: weeklyItems.length,
      createdThisWeek: weeklyItems.length,
      averagePerDay: Math.round((weeklyItems.length / 7) * 100) / 100,
      generatedAt: new Date().toISOString()
    };

    // Group by date for daily breakdown
    const dailyStats = {};
    weeklyItems.forEach(item => {
      const date = item.createdAt.split('T')[0];
      dailyStats[date] = (dailyStats[date] || 0) + 1;
    });

    const report = {
      period: {
        start: weekStartISO,
        end: new Date().toISOString()
      },
      summary: stats,
      dailyBreakdown: dailyStats
    };

    console.log('📈 Weekly Report Summary:');
    console.log(`- Total items created this week: ${stats.createdThisWeek}`);
    console.log(`- Average per day: ${stats.averagePerDay}`);
    console.log('- Daily breakdown:', JSON.stringify(dailyStats, null, 2));

    // In a real application, you might:
    // - Save report to a file
    // - Send via email
    // - Store in a separate reports table
    // - Send to monitoring service

    return report;

  } catch (error) {
    console.error('❌ Report generation failed:', error);
    throw error;
  }
}

module.exports = { generateReports };