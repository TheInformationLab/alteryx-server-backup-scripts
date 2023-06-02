# create parameter for ssl cert location
Param(
    [Parameter(Mandatory=$true)]
    [string]$certPath
)

# Import-PfxCertificate -Password (ConvertTo-SecureString -String "truststore_password" -AsPlainText -Force) -CertStoreLocation Cert:\LocalMachine\Root -FilePath truststore_filepath

$params = @{
    FilePath = $certPath
    CertStoreLocations = 'Cert:\LocalMachine\My'
}
Import-Certificate @params

# install ssl cert to personal store

# Import-PfxCertificate  -FilePath $certPath -CertStoreLocation Cert:\LocalMachine\My

