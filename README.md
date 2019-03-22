# AWSLogin
## About AWSLogin
Brought to you out of the kindness of my heart (read: boredom) this is the second half of tools to support pure(ish) PowerShell login to the AWS CLI tool via Okta SSO in a fairly simple and somewhat janky way. This is fairly basic, and pretty much just calls STS:AssumeRoleWithSAML for you. This module requires its sister OktaLogin available at https://github.com/bad2beef/OktaLogin .

Okta has a Java applet to do this. Several other projects exist as well. Why another one? Again, I was bored. But more importantly I like to compute fairly light. Having a pure PowerShell way to do this suits my day-to-day a bit better than other options.

## Installation
This is a simple pure PowerShell module. Install it the way you would install any other. 
```powershell
PS> Install-Module -Name AWSLogin
PS>
```

For manual installation simply copy the contents of the repository into `Modules\AWSLogin` and you should be ready to go. Using `git clone` makes updating later on easy.
```powershell
PS> Set-Location $env:PSModulePath.Split( ';' )[0]
PS> git clone git@github.com:bad2beef/AWSLogin.git
Cloning into 'AWSLogin'...
remote: Counting objects: 4, done.
remote: Compressing objects: 100% (4/4), done.
remote: Total 4 (delta 0), reused 4 (delta 0), pack-reused 0
Receiving objects: 100% (4/4), done.
PS>
```

## Usage
The module exports the Get-AWSToken cmdlet. There are three ways to use it.
1. __Stored Profiles__ – Store role data in a configuration file to log in as quickly as possible each time. `Get-AWSToken -Profile MyProfile`
2. __Manual Login__ – Explicitly pass Role and IdP ARNs for flexible, one-command authentication. `Get-AWSToken -OktaAppURI 'https://mycompany.okta.com/home/SomeApp/AppID/Instance' -RoleARN 'arn:aws:iam::XXXXXXXXXXXX:role/RoleToAssume' -PrincipalARN 'arn:aws:iam::XXXXXXXXXXXX:saml-provider/MySAMLProvider'`
3. __Interactive Menu__ – Declare only the Okta App URI, leaving the Role and IdP ARNs empty, and get prompted to select from a list of roles to assume. This works for both Stored Profiles and Manual Login. `Get-AWSToken -OktaAppURI 'https://mycompany.okta.com/home/SomeApp/AppID/Instance'`

## Configuration
The only configuration supported is stored connection profiles. This is a list of one or more items in a CSV file with for elements: _Name_, _OktaAppURI_, _RoleARN_, _PrincipalARN_. Only _Name_ and _OktaAppURI_ are required. If _RoleARN_ or _PrincipalARN_ are empty _Get-AWSToken_ will display an interactive menu to select a target role.

1. Create file AWSLogin.csv in the module directory, $env:APPDATA, or the user's Documents directory (use the user's home directory if using PowerShell Core.)
2. Set the following header. `"Name","OktaAppURI","RoleARN","PrincipalARN"`
3. Add rows as appropriate.

## Examples
A fully pre-defined profile entry in the configuration file.
### Pre-Defined Role From Profile
```
PS> Get-AWSToken -Profile MyProfile
PS>
```

### Interactive Menu from Profile
A pre-defined profile entry consisting of only _Name_ and _OktaAppURI_ fields.
```powershell
PS> Get-AWSToken -Profile MyProfile
cmdlet Get-Credential at command pipeline position 0
Supply values for the following parameters:
Credential
Select a role to assume.

  Account 000000000001
     1: Role-01

  Account 000000000002
     2: Role-02

  Account 000000000003
     3: Role-03

  Account 000000000004
     4: Role-04
Role (1-4): 4
PS>
```

### Manual Role Specification
This example uses the full Okta application URI, role ARN and IdP principal ARN. It will prompt for Okta credentials and store token data in the current shell’s environment. This allows you to have multiple consoles with different credentials loaded without having to force switch profiles in the fly.
```powershell
PS> Get-AWSToken `
        -OktaAppURI 'https://mycompany.okta.com/home/SomeApp/AppID/Instance' `
        -RoleARN 'arn:aws:iam::XXXXXXXXXXXX:role/RoleToAssume' `
        -PrincipalARN 'arn:aws:iam::XXXXXXXXXXXX:saml-provider/MySAMLProvider'
PS>
```

### Specific MFA Login
This option allows you to force a particular supported MFA type and/or specify the MFA code ahead of time if it is known (TTOP).
```powershell
PS> Get-AWSToken `
        -OktaAppURI 'https://mycompany.okta.com/home/SomeApp/AppID/Instance' `
        -RoleARN 'arn:aws:iam::XXXXXXXXXXXX:role/RoleToAssume' `
        -PrincipalARN 'arn:aws:iam::XXXXXXXXXXXX:saml-provider/MySAMLProvider' `
        -MFAType 'token:software:totp' `
        -MFACode 123456
PS>
```
