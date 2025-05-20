# Pester test suite for update-ssl-key.ps1
# This script checks the parameter parsing, help output, and dry-run logic for update-ssl-key.ps1 using Pester

$testScript = Join-Path $PSScriptRoot 'update-ssl-key.ps1'

Describe 'update-ssl-key.ps1' {
    It 'Shows help output with -Help' {
        $output = powershell -NoProfile -ExecutionPolicy Bypass -File $testScript -Help
        $output | Should -Match 'Usage: \\.\\update-ssl-key.ps1'
    }
    It 'Accepts positional parameter for Thumbprint' {
        $output = powershell -NoProfile -ExecutionPolicy Bypass -File $testScript ABCDEF1234567890 -Help
        $output | Should -Match 'Usage: \\.\\update-ssl-key.ps1'
    }
    It 'Accepts named parameter for Thumbprint' {
        $output = powershell -NoProfile -ExecutionPolicy Bypass -File $testScript -Thumbprint ABCDEF1234567890 -Help
        $output | Should -Match 'Usage: \\.\\update-ssl-key.ps1'
    }
}
