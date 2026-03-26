# Test script for the action - now supports both input formats
# Demonstrates newline-separated format (recommended) and JSON array format

# Test with various registries using newline-separated format
$imageUrls = @'
ghcr.io/optivem/atdd-accelerator-template-dotnet/monolith:latest
nginx:latest
'@

# Create a temporary output file to simulate GITHUB_OUTPUT
$tempOutputFile = Join-Path $env:TEMP "github_output_refactored_test.txt"
Write-Output "Using temporary output file: $tempOutputFile"

# Run the action script
try {
    Write-Output "🧪 Testing the action - returns JSON array of digest URLs..."
    Write-Output "Format: Newline-separated (recommended)"
    Write-Output "Output: JSON array of digest URLs (preserves input order)"
    Write-Output ""
    Write-Output "Images to test:"
    Write-Output "  1. ghcr.io/optivem/atdd-accelerator-template-dotnet/monolith:latest"
    Write-Output "  2. nginx:latest"
    Write-Output ""
    
    # Call the action script with newline-separated image URLs
    & ".\action.ps1" -ImageUrls $imageUrls -GitHubOutput $tempOutputFile
    
    Write-Output ""
    Write-Output "📄 Contents of simulated GitHub output file:"
    if (Test-Path $tempOutputFile) {
        Get-Content $tempOutputFile
    } else {
        Write-Output "No output file was created."
    }
    
    # Test JSON format as well
    Write-Output ""
    Write-Output "🧪 Testing JSON array format..."
    $jsonImageUrls = '["hello-world:latest", "nginx:latest"]'
    & ".\action.ps1" -ImageUrls $jsonImageUrls -GitHubOutput $tempOutputFile
    
    Write-Output ""
    Write-Output "📄 Contents of simulated GitHub output file:"
    if (Test-Path $tempOutputFile) {
        Get-Content $tempOutputFile
    } else {
        Write-Output "No output file was created."
    }
    
} catch {
    Write-Error "❌ Test failed: $($_.Exception.Message)"
} finally {
    # Clean up
    if (Test-Path $tempOutputFile) {
        Remove-Item $tempOutputFile -Force
        Write-Output ""
        Write-Output "🧹 Cleaned up temporary output file"
    }
}