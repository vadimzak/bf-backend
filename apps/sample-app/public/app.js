// API Base URL - will be updated when deployed
const API_BASE = window.location.origin;

// Show section based on navigation
function showSection(sectionId) {
    document.querySelectorAll('.section').forEach(section => {
        section.classList.remove('active');
    });
    document.getElementById(sectionId).classList.add('active');
    
    // Load section-specific data
    if (sectionId === 'items') {
        loadItems();
    } else if (sectionId === 'api') {
        loadApiInfo();
    }
}

// Check server health on load
async function checkHealth() {
    try {
        const response = await fetch(`${API_BASE}/health`);
        const data = await response.json();
        
        const healthStatus = document.getElementById('health-status');
        healthStatus.classList.add('healthy');
        healthStatus.innerHTML = `
            <p><strong>Server Status:</strong> ${data.status}</p>
            <p><strong>Service:</strong> ${data.service}</p>
            <p><strong>Timestamp:</strong> ${new Date(data.timestamp).toLocaleString()}</p>
        `;
    } catch (error) {
        const healthStatus = document.getElementById('health-status');
        healthStatus.innerHTML = `<p style="color: red;">Failed to connect to server</p>`;
    }
}

// Load items from DynamoDB
async function loadItems() {
    const itemsList = document.getElementById('items-list');
    itemsList.innerHTML = '<p>Loading items...</p>';
    
    try {
        const response = await fetch(`${API_BASE}/api/items`);
        const data = await response.json();
        
        if (data.success && data.items.length > 0) {
            itemsList.innerHTML = data.items.map(item => `
                <div class="item-card">
                    <div class="item-info">
                        <h4>${item.name || 'Unnamed Item'}</h4>
                        <p>${item.description || 'No description'}</p>
                        <small>ID: ${item.id}</small>
                    </div>
                    <div class="item-actions">
                        <button onclick="deleteItem('${item.id}')">Delete</button>
                    </div>
                </div>
            `).join('');
        } else {
            itemsList.innerHTML = '<p>No items found. Add your first item above!</p>';
        }
    } catch (error) {
        itemsList.innerHTML = '<p style="color: red;">Failed to load items. Make sure DynamoDB is configured.</p>';
    }
}

// Add new item
async function addItem() {
    const name = document.getElementById('item-name').value;
    const description = document.getElementById('item-description').value;
    
    if (!name) {
        alert('Please enter an item name');
        return;
    }
    
    try {
        const response = await fetch(`${API_BASE}/api/items`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ name, description })
        });
        
        const data = await response.json();
        
        if (data.success) {
            document.getElementById('item-name').value = '';
            document.getElementById('item-description').value = '';
            loadItems();
        } else {
            alert('Failed to add item');
        }
    } catch (error) {
        alert('Failed to add item. Make sure the server is running.');
    }
}

// Delete item
async function deleteItem(id) {
    if (!confirm('Are you sure you want to delete this item?')) {
        return;
    }
    
    try {
        const response = await fetch(`${API_BASE}/api/items/${id}`, {
            method: 'DELETE'
        });
        
        const data = await response.json();
        
        if (data.success) {
            loadItems();
        } else {
            alert('Failed to delete item');
        }
    } catch (error) {
        alert('Failed to delete item');
    }
}

// Load API info
async function loadApiInfo() {
    const apiInfo = document.getElementById('api-info');
    
    try {
        const response = await fetch(`${API_BASE}/api/info`);
        const data = await response.json();
        
        apiInfo.innerHTML = JSON.stringify(data, null, 2);
    } catch (error) {
        apiInfo.innerHTML = '<p style="color: red;">Failed to load API info</p>';
    }
}

// Initialize on page load
document.addEventListener('DOMContentLoaded', () => {
    checkHealth();
});