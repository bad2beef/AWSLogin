
Function Get-AWSToken
{
  <#
    .SYNOPSIS
      Gets an AWS token via STS.

    .DESCRIPTION
      Gets an AWS token via STS. Tokens are suitable for use in API
      calls, including use of AWS CLI. By default token data is written
      to environment variables.

    .PARAMETER Profile
      Stored profile to load parameters from. Profiles are defined in
      AWSLogin.csv, in the module directory, $env:APPDATA, or
      Documents. Format "Name","OktaAppURI","RoleARN","PrincipalARN".

    .PARAMETER OktaAppURI
      The full URI to the Okta app instance. This is the URI one would
      navigate to if clicking on the application instance in the Okta
      portal.

    .PARAMETER RoleARN
      Full ARN of the AWS role to assume.

    .PARAMETER PrincipalARN
      Full ARN of the AWS-integrated Identity Provider to use.

    .EXAMPLE
      Get-AWSToken -Profile MyProfile
    
    .EXAMPLE
      Get-AWSToken `
        -OktaAppURI 'https://mycompany.okta.com/home/SomeApp/AppID/Instance' `
        -RoleARN 'arn:aws:iam::XXXXXXXXXXXX:role/RoleToAssume' `
        -PrincipalARN 'arn:aws:iam::XXXXXXXXXXXX:saml-provider/MySAMLProvider'
  #>

  [CmdletBinding()]
  Param
  (
    [Parameter(ParameterSetName='Profile', Mandatory=$true)]
    [String]$Profile,

    [Parameter(ParameterSetName='Manual', Mandatory=$true)]
    [String]$OktaAppURI,

    [Parameter(ParameterSetName='Manual', Mandatory=$true)]
    [String]$RoleARN,

    [Parameter(ParameterSetName='Manual', Mandatory=$true)]
    [String]$PrincipalARN,

    [System.Management.Automation.PSCredential]$Credential = ( Get-Credential ),

    [ValidateSet(
      'call',
      'push',
      'sms',
      'token:software:totp'
    )]
    [String]$MFAType = 'push',
    [String]$MFACode
  )

  # Verify AWS CLI command exist as we use it to get a token later.
  Try
  {
    Get-Command -Name 'aws' | Out-Null
  }
  Catch
  {
    Write-Error '''aws'' command not found.'
    return
  }

  # Load Profile if needed
  If ( $Profile ){
    $ProfileBases = @(
      ( ( Get-Module -ListAvailable 'AWSLogin' ).Path | Split-Path ),
      $env:APPDATA,
      [Environment]::GetFolderPath( 'MyDocuments' )
    )

    $ProfileDefinition = $null

    ForEach ( $ProfileBase in $ProfileBases )
    {
      $ProfilePath = ( '{0}\AWSLogin.csv' -f @( $ProfileBase ) )
      If ( Test-Path -Path $ProfilePath -ErrorAction SilentlyContinue )
      {
        $ProfileDefinition = Import-Csv -Path $ProfilePath | Where-Object { $_.Name -like $Profile }
      }
    }

    If ( $ProfileDefinition )
    {
      $OktaAppURI = $ProfileDefinition.OktaAPPUri
      $RoleARN = $ProfileDefinition.RoleARN
      $PrincipalARN = $ProfileDefinition.PrincipalARN
    }
    Else
    {
      Write-Error ( 'Profile ''{0}'' not found.' -f @( $Profile ) )
      return
    }
  }

  # Validate OKTA App URI. Must be https://domain.okta.com/some/app/path/id (ish)
  If ( -not ( $OktaAppUri -match '^https\:\/\/[\w\d\-\.]+[\w\d\-\/]+$' ) )
  {
    Write-Error 'Invalid Okta App URI.'
    return
  }

  $OktaDomain = $OktaAppUri.Split( '/' )[2]

  Write-Verbose 'Getting Okta session token.'
  $OktaSessionToken = Get-OktaSessionToken -OktaDomain $OktaDomain -Credential $Credential -MFAType $MFAType -MFACode $MFACode
  If ( -not $OktaSessionToken )
  {
    Write-Error 'Could not obtain session token.'
    return
  }

  Write-Verbose 'Getting Okta SAML assertion.'
  $OktaSAMLAssertion = Get-OktaSAMLAssertion -OktaAppURI $OktaAppURI -OktaSessionToken $OktaSessionToken
  If ( -not $OktaSAMLAssertion )
  {
    Write-Error 'Could not obtain Okta SAML assertion.'
    return
  }

  Write-Verbose 'Getting AWS token.'
  $Response = $( aws --output json sts assume-role-with-saml --role-arn $RoleARN --principal-arn $PrincipalARN --saml-assertion $OktaSAMLAssertion )

  # If we have SecretAccessKey, it all worked. Set in ENV to avoid persistence of creds on disk.
  If ( $Response -like '*SecretAccessKey*' )
  {
    $ResponseJson = $Response | ConvertFrom-Json
    $env:AWS_ACCESS_KEY_ID   = $ResponseJson.Credentials.AccessKeyId
    $env:AWS_SECRET_ACCESS_KEY = $ResponseJson.Credentials.SecretAccessKey
    $env:AWS_SESSION_TOKEN   = $ResponseJson.Credentials.SessionToken
  }
  Else
  {
    Write-Error 'Could not obtain a token.'
  }
}
