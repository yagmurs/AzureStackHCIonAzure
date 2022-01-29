[CmdletBinding()]
param (
    # source file path
    [string]$sourceUri,
    [string]$destinationUri
)


Invoke-WebRequest https://aka.ms/downloadazcopy-v10-linux -OutFile downloadazcopy-v10-linux
tar -xvf downloadazcopy-v10-linux
cp ./azcopy_linux_amd64_*/azcopy /usr/bin/
azcopy cp $sourceUri $destinationUri

if($LASTEXITCODE -ne 0){
    throw "Something went wrong, check AzCopy output or error logs."
    return
 }