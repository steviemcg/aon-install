Set-StrictMode -Version 2.0

Function Get-ParameterNamesFromCommand ([Parameter(Mandatory)] [string] $CommandName)
{
    $parameters = Invoke-Expression "(gcm $($CommandName)).Parameters"
    foreach ($h in $parameters.GetEnumerator()) {
        $h.Key
    }
}

Function Get-ParameterNamesFromSitecoreConfiguration ([Parameter(Mandatory)] [string] $Path)
{
    $json = Get-Content -Path $Path -Raw | ConvertFrom-Json
    $json.Parameters | Get-Member -MemberType NoteProperty | ForEach-Object {
        $_.Name
    }
}

Function Get-EffectiveParametersForCommand
(
    [Parameter(Mandatory)] [string] $CommandName,
    [Parameter(Mandatory)] [Hashtable] $SourceParameters
)
{
    $ParameterNames = Get-ParameterNamesFromCommand $CommandName
    Return Get-EffectiveParameters $ParameterNames $SourceParameters
}

Function Invoke-CommandWithEffectiveParameters
(
    [Parameter(Mandatory)] [string] $CommandName,
    [Parameter(Mandatory)] [Hashtable] $SourceParameters
)
{
    $Parameters = Get-EffectiveParametersForCommand $CommandName $SourceParameters
    Invoke-Expression "$CommandName @Parameters"
}

Function Get-EffectiveParameters
(
    [Parameter(Mandatory)] $ParameterNames,
    [Parameter(Mandatory)] [Hashtable] $SourceParameters
)
{
    $params = @{}
    foreach ($ParameterName in $ParameterNames.GetEnumerator()) {
        If ($SourceParameters.ContainsKey($ParameterName)) {
            $params[$ParameterName] = $SourceParameters[$ParameterName]
        }
    }

    Return $params
}