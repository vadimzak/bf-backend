const express = require('express');
const router = express.Router();
const { docClient, TABLE_NAME } = require('../config/dynamodb');
const { v4: uuidv4 } = require('uuid');

// GET /api/items - Get all items
router.get('/', async (req, res) => {
  try {
    const params = {
      TableName: TABLE_NAME
    };
    
    const data = await docClient.scan(params).promise();
    res.json({
      success: true,
      items: data.Items,
      count: data.Count
    });
  } catch (error) {
    console.error('Error fetching items:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Failed to fetch items' 
    });
  }
});

// GET /api/items/:id - Get single item
router.get('/:id', async (req, res) => {
  try {
    const params = {
      TableName: TABLE_NAME,
      Key: {
        id: req.params.id
      }
    };
    
    const data = await docClient.get(params).promise();
    
    if (!data.Item) {
      return res.status(404).json({ 
        success: false, 
        error: 'Item not found' 
      });
    }
    
    res.json({
      success: true,
      item: data.Item
    });
  } catch (error) {
    console.error('Error fetching item:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Failed to fetch item' 
    });
  }
});

// POST /api/items - Create new item
router.post('/', async (req, res) => {
  try {
    const item = {
      id: uuidv4(),
      ...req.body,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };
    
    const params = {
      TableName: TABLE_NAME,
      Item: item
    };
    
    await docClient.put(params).promise();
    
    res.status(201).json({
      success: true,
      item: item
    });
  } catch (error) {
    console.error('Error creating item:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Failed to create item' 
    });
  }
});

// PUT /api/items/:id - Update item
router.put('/:id', async (req, res) => {
  try {
    const params = {
      TableName: TABLE_NAME,
      Key: {
        id: req.params.id
      },
      UpdateExpression: 'set #data = :data, updatedAt = :updatedAt',
      ExpressionAttributeNames: {
        '#data': 'data'
      },
      ExpressionAttributeValues: {
        ':data': req.body.data,
        ':updatedAt': new Date().toISOString()
      },
      ReturnValues: 'ALL_NEW'
    };
    
    const data = await docClient.update(params).promise();
    
    res.json({
      success: true,
      item: data.Attributes
    });
  } catch (error) {
    console.error('Error updating item:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Failed to update item' 
    });
  }
});

// DELETE /api/items/:id - Delete item
router.delete('/:id', async (req, res) => {
  try {
    const params = {
      TableName: TABLE_NAME,
      Key: {
        id: req.params.id
      }
    };
    
    await docClient.delete(params).promise();
    
    res.json({
      success: true,
      message: 'Item deleted successfully'
    });
  } catch (error) {
    console.error('Error deleting item:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Failed to delete item' 
    });
  }
});

module.exports = router;