using namespace System.Net

param($Request, $TriggerMetadata)

Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{ message = 'Hello from PowerShell on Azure Functions Flex Consumption' } | ConvertTo-Json
    })
