
Function Get-AWSToken
{
    <#
        .SYNOPSIS
            Gets an AWS token via STS.

        .DESCRIPTION
            Gets an AWS token via STS. Tokens are suitable for use in API
            calls, including use of AWS CLI. By default token data is written
            to environment variables.
        
        .PARAMETER OktaAppURI
            The full URI to the Okta app instance. This is the URI one would
            navigate to if clicking on the application instance in the Okta
            portal.

        .PARAMETER RoleARN
            Full ARN of the AWS role to assume.

        .PARAMETER PrincipalARN
            Full ARN of the AWS-integrated Identity Provider to use.

        .EXAMPLE
            Get-AWSToken `
                -OktaAppURI 'https://mycompany.okta.com/home/SomeApp/AppID/Instance' `
                -RoleARN 'arn:aws:iam::XXXXXXXXXXXX:role/RoleToAssume' `
                -PrincipalARN 'arn:aws:iam::XXXXXXXXXXXX:saml-provider/MySAMLProvider'
    #>

    [CmdletBinding()]
    Param
    (
        [Parameter(Mandatory=$true)]
        [String]$OktaAppURI,

        [Parameter(Mandatory=$true)]
        [String]$RoleARN,

        [Parameter(Mandatory=$true)]
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
        $env:AWS_ACCESS_KEY_ID     = $ResponseJson.Credentials.AccessKeyId
        $env:AWS_SECRET_ACCESS_KEY = $ResponseJson.Credentials.SecretAccessKey
        $env:AWS_SESSION_TOKEN     = $ResponseJson.Credentials.SessionToken
    }
    Else
    {
        Write-Error 'Could not obtain a token.'
    }
}
