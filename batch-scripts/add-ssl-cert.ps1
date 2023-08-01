# create parameter for SSL cert location
Param(
    [Parameter(Mandatory=$true)]
    [string]$certPath,
    [string]$ipport = "0.0.0.0:443",
    [string]$fullDomain = "information.co.uk"
)

$domain = $fullDomain.Split('.')[0]

$params = @{
    FilePath = $certPath
    CertStoreLocation = 'Cert:\LocalMachine\My'
    Exportable = $true
}

Import-PfxCertificate @params

$thumb = Get-ChildItem -Path 'cert:\LocalMachine\My' | 
    Where-Object {$_.Subject -like "*$domain*" } | 
    Select -ExpandProperty Thumbprint

$params_http = @{
    IpPort = $ipport
    CertificateHash = $thumb
    ApplicationId = '{eea9431a-a3d4-4c9b-9f9a-b83916c11c67}'
    CertificateStoreName = 'My'
    NullEncryption = $false
}

Add-NetIPHttpsCertBinding @params_http
