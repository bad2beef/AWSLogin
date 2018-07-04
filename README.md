# AWSLogin
## About AWSLogin
Brought to you out of the kindness of my heart (read: boredom) this is the second half of tools to support pure(ish) PowerShell login to the AWS CLI tool via Okta SSO in a fairly simple and somewhat janky way. This is fairly basic, and pretty much just calls `aws sts assume-role-with-saml` for you. This module requires its sister OktaLogin available at https://github.com/bad2beef/OktaLogin .

Okta has a Java applet to do this. Several other projects exist as well. Why another one? Again, I was bored. But more importantly I like to compute fairly light. Having a pure PowerShell way to do this suits my day-to-day a bit better than other options.

## Installation
This is a simple pure PowerShell module. Simply copy the contents of the repository into `Modules\AWSLogin` and you should be ready to go.
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

## Examples
### Basic Login
This example (the only invocation pattern that works right now) requires the full Okta application URI, role ARN and IDP principal ARN. It will prompt for Okta credentials and store token data in the current shell’s environment. This allows you to have multiple consoles with different credentials loaded without having to force switch profiles in the fly.
```powershell
PS> Get-AWSToken `
        -OktaAppURI 'https://mycompany.okta.com/home/SomeApp/AppID/Instance' `
        -RoleARN 'arn:aws:iam::XXXXXXXXXXXX:role/RoleToAssume' `
        -PrincipalARN 'arn:aws:iam::XXXXXXXXXXXX:saml-provider/MySAMLProvider'
```
