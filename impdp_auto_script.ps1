# Script CBH-1
<# .SYNOPSIS
     Oracle Refresh Automation
.DESCRIPTION
     Target schemas: DEVHRDATA and DEVHRCTL in DEV
     Source schemas: PRODHRDATA and PRODHRCTL in PROD
     Task          : Refresh target schemas with source schemas via impdp and execute post sql.
.NOTES
     Author                       : VCNTQA
     Supported Powershell Version : 5.1
     Date                         : 22/01/2021
     Last modified Date           : 06/02/2021
     Version 1.4                  : 25/02/2021
#>


# --------------------------------[User-defined Variables]-------------------------------- #
$Date                    = Get-Date -Format "dd-MM-yyyy"                 # Dump file date format. EX.31-01-2021

### Server parameters :
$Hostname                = $env:computername                             # Script executes on this server

### Directories and file names
$Source_Dir              = '\\DC1PROD\data_expdp'                        # Network share directory where to find Dump file           
$Source_File             = "EXPDP_DC1PROD_FULL_$Date.DMP"                # Dump file name on the $Source_Host             
$Source_OK_File          = 'expdp_DC1PROD_ok.log'                        # Expdp OK file name on the $Source_Host

$Target_Dir              = 'J:\IMPDP_AUTO'                               # Dump file dir on the $Target_Host 
$Target_File             = $Source_File
$Target_Log_File         = "impdp_auto_refresh_$Date.log"                # Script logfile on the $Target_Host$Target_Dir 
$Target_OK_File          = 'impdp_auto_refresh_ok.log'                   # Impdp OK file name $Target_Dir                      

$Passfile_Dir            = 'D:\Script'                                   # Password file dir on $Target_Host

### Refresh parameters :
$DB_Env_Name             = 'HR'                                          # Database environment name

### Database connection string and Impdp parameters :
$DB_User                 = 'System'                                      # Connect to DB as User SYSTEM for sqlplus and impdp                       
$DB_Instance             = 'HRDEV'                                       # Database instance name             
$DB_Target_Host          = $Hostname  

$SOURCE_SCHEMA           = 'PRODHRDATA','PRODHRCTL'                                                                       # Schemas to import
$TARGET_SCHEMA           = 'DEVHRDATA','DEVHRCTL'                                                                         # Schemas to refresh 
$REMAP_SCHEMA            = 'PRODHRDATA:DEVHRDATA,PRODHRCTL:DEVHRCTL'                                                      # Impdp parameter REMAP_SCHEMA for schemas 
$REMAP_TABLESPACE        = 'PRODHRDATAT:DEVHRDATAT,PRODHRDATAI:DEVHRDATAI,PRODHRCTLT:DEVHRCTLT,PRODHRCTLI:DEVHRCTLI'      # Impdp parameter REMAP_TABLESPACE for tablespace
$EXCLUDE_OBJECT          = 'TRIGGER'                                            

$Impdp_Dir               = 'IMPDP_AUTO_DIR'                               # DB data pump directory for impdp            
$Impdp_Log               = "IMPORT_DC1PROD_HR_$Date.LOG"                  # Impdp log file
$Ignore_ORA              = 'ORA-39082|ORA-39083|ORA-01917'                # Ignore ora error : ORA-39082: object type create with compilation errors
																	      # Ignore ora error : ORA-39083: Object type OBJECT_GRANT failed to create with error
																	      # Ignore ora error : ORA-01917: user or role 'PRODHRDATA_READ' 'PRODHRCTL_READ' does not exist  															   
																	   
### Post SQL 
$PostSQL_Dir             = 'D:\Script'                                    # Post SQL directory                                                      
$PostSQL_Files           = @('impdp_auto_1-postsql_update_hr.sql',        # Post SQL script 1 
                             'impdp_auto_2-postsql_update_ad.sql',        # Post SQL script 2
                             'impdp_auto_3-postsql_update_pt.sql',        # Post SQL script 3
                             'impdp_auto_4-postsql_update_bk.sql')        # Post SQL script 4
                                  

### Enable/Disable Email Notification:
$Email_Notif             = $TRUE                                          # Options: TRUE - Enable email notification; FALSE - Disable email notification
$Smtp_Server             = 'smtp.mailbox.biz'                             # Email SMTP Server                       
$Smtp_Port               = '25'                                           # Email SMTP Server Port                         
$User_From               = 'itservice@support.com'                        # Email to send notification                     
$User_To                 = ('VCNTQA@support.com','dbservice@support.com') # Email to receive notification


# --------------------------------[Script-defined Variables]-------------------------------- #
$Script_Name          = $MyInvocation.MyCommand.Name
$Script_Version       = '1.4'
$Date_FormatLog       = 'dd-MM-yyyy HH:mm:ss' 

$Log_File_Filter      = '*.log'
$Dump_File_Filter     = '*.DMP'

$Complete_S           = '__Main__Completed successfully.'
$Complete_E           = '__Main__Completed with error.'
$Complete_W           = '__Main__Completed with warning.'

$Target_Disk_Filter = "DeviceId='$($Target_Dir.substring(0, 2))'"

$Passfile_DB          = 'impdp_auto_passfile_db.txt'                     # DB user password file                        

$bin_cmd              = 'cmd.exe'
$bin_impdp            = 'impdp.exe'
$bin_sqlplus          = 'sqlplus.exe'
$Required_Binaries    = @($bin_cmd, $bin_impdp, $bin_sqlplus)

$SQLPLUS_Params       = "SET ECHO ON`nSET`nWHENEVER SQLERROR EXIT SQL.SQLCODE`nWHENEVER OSERROR EXIT`n"


# --------------------------------[Mails content]-------------------------------- #
$Date_FormatMail      = '%A %d %B %Y %T'                                  
$Mail_Subject_Alert   = " [Alert] Automation Refresh $DB_Env_Name Failed"
$Mail_Subject_Info    = " [Info] Automation Refresh $DB_Env_Name Successfully"
$Mail_Subject_Warning = " [Warning] Automation Refresh $DB_Env_Name Completed with Warnings"
$Mail_Check_Log       = " Please check the log file $Target_Dir\$Target_Log_File on $Hostname for more details."


# ---------------------------------------[Functions]--------------------------------------- #

### Function LogWrite: Output infomation to log file
Function LogWrite {
    Param([string]$loglevel,[string]$logstring)
    $logtime = Get-Date -Format $Date_FormatLog
    if ($loglevel -eq ''){
        $log = "$logstring"
    }
    else{
        $log = "$logtime $($loglevel.padright(10,' ')) $logstring"
    }

    Add-Content $Log_fd -Value $log 
} 


### Function SendMail: Send mail
Function SendMail {
    Param([string]$mailsubject,[string]$mailbody)    
    if ($Email_Notif){
        $mailbodysignature             = "`n`n *Message generated by script $Script_Name version $Script_Version on host $Hostname."
        # Define the Send-MailMessage parameters
        $mailParams = @{
            SmtpServer                 = $Smtp_Server
            Port                       = $Smtp_Port
            UseSSL                     = $false
            From                       = $User_From
            To                         = $User_To
            Subject                    = $mailsubject
            Body                       = $mailbody + $mailbodysignature
            DeliveryNotificationOption = 'OnFailure'
        }
        # Send the message
        Send-MailMessage @mailParams
    }
}


### Function: check log and count errors and warnings, output infos to the end of log
Function EndJob {
    $File_Content = Get-Content "$Target_Dir\$Target_Log_File"
    $Warnings     = Select-String -InputObject $File_Content -Pattern ([regex]::Escape('[WARNING]')) -AllMatch
    $Errors       = Select-String -InputObject $File_Content -Pattern ([regex]::Escape('[ERROR]'))   -AllMatch
    $Warning_C    = $Warnings.Matches.Count
    $Error_C      = $Errors.Matches.Count
    $Elapsed_Time = "{0:HH:mm:ss}" -f ([datetime]($(Get-Date) - $StartTime).Ticks)
    $Elapsed_Info = " on $(Get-Date) elapsed $Elapsed_Time."

    LogWrite '' ("-"*150)
    if ($warning_c     -eq 0 -and $error_c -eq 0){       
        LogWrite '' "Job completed successfully $Elapsed_Info"
        $Mail_Subject  = $Mail_Subject_Info
        $Mail_Body     = "Job completed successfully $Elapsed_Info"
    }
    elseif ($warning_c -eq 0){
        LogWrite '' "Job completed with $Error_C error(s) $Elapsed_Info"
        $Mail_Subject  = $Mail_Subject_Alert
        $Mail_Body     = "Job completed with $Error_C error(s) $Elapsed_Info $Mail_Check_Log"
    }
    elseif ($error_c   -eq 0){
        LogWrite '' "Job completed with $Warning_C warning(s) $Elapsed_Info"
        $Mail_Subject  = $Mail_Subject_Warning
        $Mail_Body     = "Job completed with $Warning_C warning(s) $Elapsed_Info $Mail_Check_Log"
    }
    else {
        LogWrite '' "Job completed with $Warning_C warning(s) and $Error_C error(s) $Elapsed_Info"
        $Mail_Subject  = $Mail_Subject_Alert
        $Mail_Body     = "Job completed with $Warning_C warning(s) and $Error_C error(s) $Elapsed_Info $Mail_Check_Log"
    }
    LogWrite '' ("-"*150)
    
    $Date = Get-Date -UFormat "$Date_FormatMail"
    SendMail "$Mail_Subject - $Date" $Mail_Body
    Exit
}


# ------------------------------------------[Main]------------------------------------------ #
$StartTime = Get-Date

# Create log file
try {
    $Log_fd    = New-Item -Path $Target_Dir -Name $Target_Log_File -ItemType "file"  -Force
}
catch{
    $Mail_Body = "Job failed - Could not write to logfile $Target_Dir\$Target_Log_File"
    $Date      = Get-Date -UFormat "$Date_FormatMail"
    SendMail "$Mail_Subject_Alert - $Date" $Mail_Body
    Exit
}

foreach ($Binary in $Required_Binaries) {
    if ($(Get-Command $Binary -ErrorAction silentlycontinue).count -eq 0) {
        LogWrite '[ERROR]' "Could not find binary $Binary!"
        EndJob
    }
}


# Print script description to logfile
LogWrite '' ("-"*150)
LogWrite '' "Refresh schemas from PROD to DEV."       
LogWrite '' ("-"*150)
LogWrite '[INFO]' "Script $Script_Name version$Script_Version starts on $(Get-Date -UFormat "$Date_FormatMail")."


### Check if the source dump file is OK
LogWrite '[INFO]' "__Main__Checking dump file ......"
try {
    if ((Test-Path -path "$Source_Dir\$Source_OK_File") -And (Test-Path -path "$Source_Dir\$Source_File")) { 
        LogWrite '[INFO]' "The dump file $Source_File was exported and found correctly!"
    }
    else {
        LogWrite '[ERROR]' "The dump file $Source_File was exported with error or not found!"
        LogWrite '[INFO]' "$Complete_E"
        EndJob
    }
}
catch {
    LogWrite '[ERROR]' "$_.Exception"
    EndJob
}


### Clean old and tmp files in $Target_Dir
LogWrite '[INFO]' '__Main__Removing old files ......' 
try {
    $File_List = Get-ChildItem -Path $Target_Dir -File | where-object {($_.Name -like $Log_File_Filter ) -or ($_.Name -like $Dump_File_Filter )} | Where-Object {($_.LastWriteTime -lt (Get-Date).AddDays(-6)) -or $_.name -eq $Target_OK_File}

    if ($File_List.count -gt 0){
		LogWrite '[INFO]' "The following files have been removed:"
		foreach ($file in $File_List){
			Remove-Item "$Target_Dir\$file"
			LogWrite '[INFO]' "- $file"
		}
	}
    LogWrite '[INFO]' "$Complete_S"
}
catch {
    LogWrite '[ERROR]' "$_.Exception"
}


### Check free disk space on target directory
LogWrite '[INFO]' "__Main__Checking free disk space ......"
try {
    $Dump_File_Size 	   = (Get-Item "$Source_Dir\$Source_File").Length
    $Target_Disk_Freespace = (Get-Item "$Target_Dir").psdrive.Free         # Get free disk size of disk 
    if($Target_Disk_Freespace -ge ($Dump_File_Size + 10GB) ) {             # Enough disk space
        LogWrite '[INFO]'    "There is enough free disk space on $Target_Dir."
        LogWrite '[INFO]'    "$Complete_S"
    }
    elseif($Target_Disk_Freespace -ge ($Dump_File_Size + 2GB)) {           # Limited disk space
        LogWrite '[WARNING]' "Limited free disk space on $Target_Dir. Please check the free disk space on $Target_Dir." 
        LogWrite '[INFO]'    "$Complete_W"
    }
    else {                                                                 # No enough disk space
        LogWrite '[ERROR]'   "There isn't enough free disk space on $$Target_Dir, can't copy dump file, please check disk space!"
        LogWrite '[INFO]'    "$Complete_E"
        EndJob
    }
}
catch {
    LogWrite '[ERROR]' "$_.Exception"
    EndJob
}

### Copy dump file
LogWrite '[INFO]' '__Main__Copying dump file ......'
try {
	$Copy_Needed               = $True                                     # By default, copy is needed
	if (Test-Path -path "$Target_Dir\$Target_File") {
		$Target_Dump_File_Size = (Get-Item "$Target_Dir\$Target_File").Length
		if ( $Target_Dump_File_Size -eq $Dump_File_Size ){
			$Copy_Needed       = $False                                    # If file already exists on target with right size, we can skip the copy of dump file
		}
	} 
	if ($Copy_Needed) { Copy-Item "$Source_Dir\$Source_File" -Destination "$Target_Dir\$Target_File" -ErrorAction Stop }
}
catch { 
    LogWrite '[ERROR]' "$_.Exception"
    LogWrite '[INFO]'  "$Complete_E"
    EndJob    
}

LogWrite '[INFO]' "The dump file $Source_File was copied successfully!"
LogWrite '[INFO]' "$Complete_S"  


### Define connection string to target DB
$DB_Pass              = Get-Content -Path "$Passfile_Dir\$Passfile_DB"                     
$DB_Connection_String = "$DB_User/$DB_Pass@$DB_Target_Host/$DB_Instance" 


### Connect to target database and drop schema
LogWrite '[INFO]' "__Main__Connecting to database and dropping schema......"
$Drop_Schema        = "$SQLPLUS_Params"

$TARGET_SCHEMA | foreach { $Drop_Schema += "DROP USER $_ CASCADE;`n"}

$Result_Drop_Schema = $Drop_Schema | &$bin_sqlplus $DB_Connection_String 
$Result_Drop_Schema | Where-Object { $_ -ne ""} | foreach { LogWrite '[INFO]' "$_" }


$Error_Result_Drop_Schema = (Select-String -InputObject $Result_Drop_Schema -Pattern 'ORA-' -AllMatches ).Matches.Count
if ($Error_Result_Drop_Schema -gt 0){
    LogWrite '[ERROR]' "Drop Schema Failed !"
    LogWrite '[INFO]'  "$Complete_E"
    EndJob
}
else{
    LogWrite '[INFO]' "$Complete_S"
}

### Start impdp 
$Impdp_Params   = "$DB_Connection_String DIRECTORY=$Impdp_Dir DUMPFILE=$Target_File LOGFILE=$Impdp_Log SCHEMAS=$([string]::join(',',$SOURCE_SCHEMA)) REMAP_SCHEMA=${REMAP_SCHEMA} REMAP_TABLESPACE=${REMAP_TABLESPACE} EXCLUDE=${EXCLUDE_OBJECT}"
LogWrite '[INFO]' "__Main__Connecting to database and importing schemas ......"
$Impdp_Command  = "$bin_impdp $Impdp_Params"
$IMPDP_Result   = &$bin_cmd "/c $Impdp_Command"  2>&1
# https://docs.oracle.com/database/121/SUTIL/GUID-34D0DEE7-3530-42DC-BE01-C2588CC73CE5.htm#SUTIL3834
$IMPDP_ExitCode = $LASTEXITCODE

LogWrite '[INFO]' "Impdp log file: $Impdp_Log"

$ORA_EX_SUCC        = 0     #The export or import job completed successfully. No errors are displayed to the output device or recorded in the log file, if there is one.
$ORA_EX_SUCC_ERR    = 5     #The export or import job completed successfully but there were errors encountered during the job. The errors are displayed to the output device and recorded in the log file, if there is one.
$ORA_EX_FAIL        = 1     #The export or import job encountered one or more fatal errors

if ($IMPDP_ExitCode     -eq $ORA_EX_SUCC ) {
    LogWrite '[INFO]' "The import job completed successfully. No errors are recorded in the log file $Impdp_Log"
    LogWrite '[INFO]' "$Complete_S"
}
elseif ($IMPDP_ExitCode -eq $ORA_EX_SUCC_ERR ) {
    $Error_Result_Impdp_Schema = (Select-String -InputObject (Get-Content "$Target_Dir\$Impdp_Log") -Pattern 'ORA-' -AllMatches ).Matches.Count
    $Error_Result_Impdp_Schema_ORA = (Select-String -InputObject (Get-Content "$Target_Dir\$Impdp_Log") -Pattern "$Ignore_ORA" -AllMatches ).Matches.Count
    if ($Error_Result_Impdp_Schema -ne $Error_Result_Impdp_Schema_ORA){
        LogWrite '[ERROR]' "The import job completed successfully but there were errors encountered during the job. The errors are recorded in the log file $Impdp_Log"
        LogWrite '[INFO]' "$Complete_E"
        EndJob
    }
    else{
        LogWrite '[INFO]' "The import job completed successfully with "$Ignore_ORA" errors during the job. These errors could be ingored and are recorded in the log file $Impdp_Log"
        LogWrite '[INFO]' "$Complete_S"
    }
}
elseif ($IMPDP_ExitCode -eq $ORA_EX_FAIL ){ 
    LogWrite '[ERROR]' "The import job import job encountered one or more fatal errors."
    $IMPDP_Result | Where-Object { $_ -ne ""} | foreach { LogWrite '[INFO]' "$_" }
    LogWrite '[INFO]' "$Complete_E"
    EndJob    
}


### Alter schema password
$Alter_Schema        = "$SQLPLUS_Params"
$TARGET_SCHEMA | foreach { $Alter_Schema += "Alter USER $_ IDENTIFIED BY $_;`n" }
LogWrite '[INFO]' "__Main__Connecting to database and altering schema ......"

$Result_Alter_Schema = $Alter_Schema | &$bin_sqlplus $DB_Connection_String 
$Result_Alter_Schema | Where-Object { $_ -ne ""} | foreach { LogWrite '[INFO]' "$_" }

$Error_Result_Alter_Schema = (Select-String -InputObject $Result_Alter_Schema -Pattern 'ORA-' -AllMatches ).Matches.Count
if ($Error_Result_Alter_Schema -gt 0) {
    LogWrite '[ERROR]' "Alter Schema Failed !"
    LogWrite '[INFO]' "$Complete_E"
    EndJob
}
else{
    LogWrite '[INFO]' "$Complete_S"
}


### Post-SQL to be executed
LogWrite '[INFO]' "__Main__Executing PostSQL scripts ......"
try {
	$Error_Found               = $False                          # By default
    foreach ($script_file in $PostSQL_Files) { 
		$PostSQL_Params        = "$SQLPLUS_Params @$PostSQL_Dir\$script_file`n" 
		$Result_PostSQL_Script = $PostSQL_Params | &$bin_sqlplus $DB_Connection_String | Tee-Object -FilePath "$Target_Dir\$script_file-$Date.log"
		$nb_PostSQL_Errors     = (Select-String -InputObject $Result_PostSQL_Script -Pattern 'ORA-' -AllMatches ).Matches.Count
		if ($nb_PostSQL_Errors -gt 0){
			LogWrite '[ERROR]' "PostSQL $script_File Executation Failed. The errors are recorded in the log file $script_file-$Date.log !"
			$Error_Found       = $True
		}
		else{
			LogWrite '[INFO]' "PostSQL $script_file Executation Success. Details are recorded in the log file $script_file-$Date.log !"
		}
	}
	if ($Error_Found) {
		LogWrite '[INFO]' "$Complete_E"
		EndJob 
	}
    else {
        LogWrite '[INFO]' "$Complete_S"
    }
}
catch {
    LogWrite '[ERROR]' "$_.Exception"
    EndJob
}

### At his point, impdp was succesful with no major error => we create an ok file : this file could be used for monitoring 
try {
     New-Item -Path $Target_Dir -Name $Target_OK_File -ItemType "file"  -Force         
}
catch {
    LogWrite '[ERROR]' "$_.Exception"
}

LogWrite '[INFO]' '__Main__Removing dmp file ......' 
try {
    Remove-Item "$Target_Dir\$Target_File"
    LogWrite '[INFO]' "$Target_Dir\$Target_File was deleted."
    LogWrite '[INFO]' "$Complete_S"
}
catch {
    LogWrite '[ERROR]' "$_.Exception"
}

EndJob
