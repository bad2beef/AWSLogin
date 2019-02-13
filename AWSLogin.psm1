
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

    .EXAMPLE
      Get-AWSToken -OktaAppURI 'https://mycompany.okta.com/home/SomeApp/AppID/Instance'
  #>

  [CmdletBinding()]
  Param
  (
    [Parameter(ParameterSetName='Manual', Mandatory=$true)]
    [String]$OktaAppURI,

    [Parameter(ParameterSetName='Manual')]
    [String]$RoleARN,

    [Parameter(ParameterSetName='Manual')]
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

  DynamicParam
  {
    $ParameterAttribute = New-Object -TypeName System.Management.Automation.ParameterAttribute
    $ParameterAttribute.Mandatory = $true
    $ParameterAttribute.Position = 1
    $ParameterAttribute.ParameterSetName = 'Profile'
    
    $AttributeCollection = New-Object -TypeName System.Collections.ObjectModel.Collection[System.Attribute]
    $AttributeCollection.Add( $ParameterAttribute )

    $ConfigPaths = @( # Must declare in Process as well
      ( ( Get-Module -ListAvailable 'AWSLogin' ).Path | Split-Path ),
      $env:APPDATA,
      [Environment]::GetFolderPath( 'MyDocuments' )
    )

    $Profiles = @()
    ForEach ( $ConfigPath in $ConfigPaths )
    {
      $ProfilePath = ( '{0}\AWSLogin.csv' -f @( $ConfigPath ) )
      If ( Test-Path -Path $ProfilePath -ErrorAction SilentlyContinue )
      {
        $Profiles = Import-Csv -Path $ProfilePath | Select-Object -ExpandProperty Name
      }
    }

    $AttributeCollection.Add( ( New-Object -TypeName System.Management.Automation.ValidateSetAttribute( $Profiles ) ) )
    
    $RuntimeParameter = New-Object System.Management.Automation.RuntimeDefinedParameter( 'Profile', [String], $AttributeCollection )
    $RuntimeParameterDictionary = New-Object -TypeName System.Management.Automation.RuntimeDefinedParameterDictionary
    $RuntimeParameterDictionary.Add( 'Profile', $RuntimeParameter )

    return $RuntimeParameterDictionary
  }

  Process
  {
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
    If ( $PsBoundParameters.Profile ){
      $ProfileDefinition = $null

      $ConfigPaths = @( # Must declare in DynamicParam as well
        ( ( Get-Module -ListAvailable 'AWSLogin' ).Path | Split-Path ),
        $env:APPDATA,
        [Environment]::GetFolderPath( 'MyDocuments' )
      )

      ForEach ( $ConfigPath in $ConfigPaths )
      {
        $ProfilePath = ( '{0}\AWSLogin.csv' -f @( $ConfigPath ) )
        If ( Test-Path -Path $ProfilePath -ErrorAction SilentlyContinue )
        {
          $ProfileDefinition = Import-Csv -Path $ProfilePath | Where-Object { $_.Name -like $PsBoundParameters.Profile }
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
        Write-Error ( 'Profile ''{0}'' not found.' -f @( $PsBoundParameters.Profile ) )
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

    # If no ARNs provided parse assertion for roles.
    If ( ( -not $RoleARN ) -or ( -not $PrincipalARN ) )
    {
      $OktaSAMLAssertionParsed = [XML][System.Text.Encoding]::UTF8.GetString( [System.Convert]::FromBase64String( $OktaSAMLAssertion ) )
      $PrincipalRolePairs = $OktaSAMLAssertionParsed.Response.Assertion.AttributeStatement.Attribute | Where-Object { $_.Name -like 'https://aws.amazon.com/SAML/Attributes/Role' } | Select-Object -ExpandProperty AttributeValue | Select-Object -ExpandProperty '#text' | Sort-Object
      
      [System.Collections.ArrayList]$Roles = @()
      ForEach ( $PrincipalRolePair in $PrincipalRolePairs )
      {
        $Roles.Add( @( $PrincipalRolePair.Split( ',' ) ) ) | Out-Null
      }
      
      $RoleIndex = 0
      If ( -not $Roles.Count )
      {
        Write-Error 'SAML assertion contains no identifiable roles.'
        return
      }
      ElseIf ( $Roles.Count -gt 1 )
      {
        Write-Host 'Select a role to assume.'
        $LastAccount = $Null
        For ( $Index = 0 ; $Index -lt $Roles.Count ; $Index++ )
        {
          $RoleParts = $Roles[ $Index ][1].Split( @( ':', '/' ) )
          If ( $RoleParts[4] -notlike $LastAcount )
          {
            $LastAccount = $RoleParts[4]
            Write-Host ''
            Write-Host ( '  Account {0}' -f @( $RoleParts[4] ) )
          }
          Write-Host ( '    {0,2}: {1}' -f @( ( $Index + 1 ), $RoleParts[6] ) )
        }

        Write-Host ''
        [Int]$RoleIndex = Read-Host -Prompt ( 'Role ({0}-{1})' -f @( 1, $Roles.Count ) )
        If ( ( $RoleIndex -lt 1 ) -or ( $RoleIndex -gt $Roles.Count ) )
        {
          Write-Error 'Invalid role index.'
          return
        }
        Else
        {
          $RoleIndex--
        }
      }

      Write-Verbose ( 'Assuming role with ARN "{0}" via IdP "{1}"' -f @( $Roles[ $RoleIndex  ][1], $Roles[ $RoleIndex ][0] ) )

      $PrincipalARN = $Roles[ $RoleIndex ][0]
      $RoleARN = $Roles[ $RoleIndex ][1]
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
}
