# Staff leaves report for Sentrifugo HRMS software 
Perl script to let your Sentrifugo generate summary report to the team managers

## Pre-requesties

1. Linux OS
2. Related software need to install :
- Perl
- Perl-DBI module
- Perl-Date-Simple module
- mutt
- Postfix and configured for send email

## How to
Provide information for below variables in the script :
- $password for your database password
- $database for your database name
- $sender for your sender email address

Just execute the script to generate the report which will send email to all team managers.
