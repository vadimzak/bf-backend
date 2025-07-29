document.addEventListener('DOMContentLoaded', function() {
    const statusBtn = document.getElementById('statusBtn');
    const statusDiv = document.getElementById('status');
    
    statusBtn.addEventListener('click', async function() {
        statusBtn.textContent = 'Checking...';
        statusBtn.disabled = true;
        
        try {
            const response = await fetch('/health');
            const data = await response.json();
            
            if (response.ok) {
                statusDiv.className = 'status success';
                statusDiv.innerHTML = `
                    <strong>✅ Service Status: ${data.status}</strong><br>
                    Service: ${data.service}<br>
                    Last check: ${new Date(data.timestamp).toLocaleString()}
                `;
            } else {
                throw new Error('Health check failed');
            }
        } catch (error) {
            statusDiv.className = 'status error';
            statusDiv.innerHTML = `
                <strong>❌ Service Status: Error</strong><br>
                Unable to connect to health check endpoint
            `;
        } finally {
            statusBtn.textContent = 'Check Status';
            statusBtn.disabled = false;
        }
    });
    
    // Add some interactive animations
    const features = document.querySelectorAll('.feature');
    features.forEach((feature, index) => {
        feature.style.animationDelay = `${index * 0.1}s`;
        feature.style.opacity = '0';
        feature.style.transform = 'translateY(20px)';
        
        setTimeout(() => {
            feature.style.transition = 'all 0.5s ease';
            feature.style.opacity = '1';
            feature.style.transform = 'translateY(0)';
        }, 100 + (index * 100));
    });
});