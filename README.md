### Powershell script for refresh data via impdp from Oracle Prod environment to Dev environment automatically

#### Tasks included in scripts
- Copy dump file from Prod to Dev
- Drop schemas (need to be refreshed) in Dev 
- Refresh data with remap schemas via impdp
- Execute POST SQL
- Send email notification

#### script and parameter files
- bat file [impdp_auto.bat](https://github.com/VCNTQA/Oracle_Windows/blob/main/impdp_auto.bat)
- Powershell file [impdp_auto_script.ps1](https://github.com/VCNTQA/Oracle_Windows/blob/main/impdp_auto_script.ps1)
- Database account credential file if needed 'impdp_auto_passfile_db.txt'
- Post SQL file if needed
