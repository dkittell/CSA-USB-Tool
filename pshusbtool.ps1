[CmdletBinding()]
param(
	[Parameter(Position = 0, Mandatory = $true)][string]$csvFile,
	[Parameter(Position = 1, Mandatory = $true)][string]$csvFilePath,
	[Parameter(Position = 2, Mandatory = $false)][string]$csvFileURL
)

$StartTime = $(get-date)
$datetime = $(get-date -f yyyy-MM-dd_hh.mm.ss)
Start-Transcript -path "$($csvFilePath)/log_$($datetime).txt"
 
# ./pshusbtool.ps1 -csvFile FTCSoftware2023.csv -csvFilePath /Users/dkittell/CSA/FTC2023/
# ./pshusbtool.ps1 -csvFile FTCSoftware2023.csv -csvFilePath /Users/dkittell/CSA/FTC2023/ -csvFileURL https://raw.githubusercontent.com/dkittell/CSA-USB-Tool/main/

# ./pshusbtool.ps1 -csvFile FRCSoftware2024.csv -csvFilePath /Users/dkittell/CSA/FRC2024/
# ./pshusbtool.ps1 -csvFile FRCSoftware2024.csv -csvFilePath /Users/dkittell/CSA/FRC2024/ -csvFileURL https://raw.githubusercontent.com/dkittell/CSA-USB-Tool/main/

if ([string]::IsNullOrWhiteSpace($csvFileURL)) {
	$csvFileURL = "https://raw.githubusercontent.com/dkittell/CSA-USB-Tool/main"
}
else {
	$csvFileURL = $csvFileURL.TrimEnd('/')
}

$csvFileURL = "$($csvFileURL)/$($csvFile)"

#region Functions
function md5hash() {
	param(
		[Parameter(Mandatory = $true)][string]$path
	)
	$fullPath = Resolve-Path $path
	$md5 = new-object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
	$file = [System.IO.File]::Open($fullPath, [System.IO.Filemode]::Open, [System.IO.FileAccess]::Read)
	try {
		[System.BitConverter]::ToString($md5.ComputeHash($file))
	}
 finally {
		$file.Dispose()
	}
}

function DownloadFile() {
	param(
		[Parameter(Mandatory = $true)][string]$WebURL,
		[Parameter(Mandatory = $true)][string]$FileDirectory,
		[Parameter(Mandatory = $false)][string]$MD5,
		[Parameter(Mandatory = $false)][string]$AltName
	)
	# If directory doesn't exist create the directory
	if ((Test-Path $FileDirectory) -eq 0) {
		New-Item $FileDirectory -ItemType Directory -Force		
	}
	if (!$AltName) {
		$FileName = [System.IO.Path]::GetFileName($WebURL)
	}
	else {
		$FileName = $AltName
	}
	# Concatenate the two values to prepare the download
	$FullFilePath = "$($FileDirectory)/$($FileName)"  
	try {
		$uri = New-Object "System.Uri" "$WebURL"
		$request = [System.Net.HttpWebRequest]::Create($uri)
		$request.set_Timeout(15000) #15 second timeout
		$response = $request.GetResponse()
		$totalLength = [System.Math]::Floor($response.get_ContentLength() / 1024)
		$responseStream = $response.GetResponseStream()
		$targetStream = New-Object -TypeName System.IO.FileStream -ArgumentList $FullFilePath, Create
		$buffer = new-object byte[] 10KB
		$count = $responseStream.Read($buffer, 0, $buffer.length)
		$downloadedBytes = $count
		while ($count -gt 0) {
			[System.Console]::Write("`r`nDownloaded {0}K of {1}K", [System.Math]::Floor($downloadedBytes / 1024), $totalLength)
			$targetStream.Write($buffer, 0, $count)
			$count = $responseStream.Read($buffer, 0, $buffer.length)
			$downloadedBytes = $downloadedBytes + $count
		} 
		$targetStream.Flush()
		$targetStream.Close()
		$targetStream.Dispose()
		$responseStream.Dispose()  
		# Give a basic message to the user to let them know what we are doing
		Write-Output "$(Get-Date) - Downloading $WebURL to $FullFilePath"		
	}
	catch {
		Write-Output "$(Get-Date) - Download had a problem with $WebURL"
		Write-Output "$(Get-Date) - Download had a problem with $WebURL" | Out-File -Append -FilePath "$($FileDirectory)/log__$($datetime)_FailedDownloads.txt"

	}
	# Check MD5
	if (($MD5)) {
		# MD5 Provided, check the MD5 of the file.
		if (!(Test-Path $FullFilePath)) {
			# File does not exist on system no need to check MD5
			Write-Output "$(Get-Date) - Unable to check MD5 as file does not exist." 
		}
		else {
			$fileHash = md5hash -path $FullFilePath
			if ($MD5 = $fileHash) {
				Write-Output "$(Get-Date) - MD5 of $WebURL ($FullFilePath) matches"
				# Give a basic message to the user to let them know we are done
				Write-Output "$(Get-Date) - Download of $WebURL ($FullFilePath) complete"
			}
			else {
				Write-Output "$(Get-Date) - MD5 of $WebURL ($FullFilePath) Incorrect, removing the file."
				try {
					Remove-Item -Path $FullFilePath -Force
				}		
				catch {
					Write-Output "$(Get-Date) - MD5 of $WebURL ($FullFilePath) Incorrect, unable to remove" 
				}
				Write-Output "$(Get-Date) - Download had a problem with $WebURL ($FullFilePath)" 
			}
		}
	}	
	else {
		if (!$FileName -like "F*CSoftware*.csv") {
			Write-Output "$(Get-Date) - MD5 of $WebURL ($FullFilePath) was not provided, please manually validate."
		}
	}
}
#endregion Functions

#region Download CSV File
$csvFile = [System.IO.Path]::GetFileName($csvFileURL)
$csvFilePath = $csvFilePath.TrimEnd('/')
DownloadFile -WebURL $csvFileURL -FileDirectory $csvFilePath
$csvList = Import-Csv -Path "$($csvFilePath)/$($csvFile)" -Header 'FriendlyName', 'FileName', 'URL', 'MD5', 'isZipped','Category'
# $csvList | Format-Table -AutoSize
#endregion Download CSV File

#region Use the CSV and download the files
$csvList | Sort-Object 'FriendlyName' | Foreach-Object {
	Write-Output "`r`n$(Get-Date) - $($_.FriendlyName)"

	if ($_.Category) {

		$localPath = "$($csvFilePath)/$($_.Category)/$($_.FileName)"
	}
	else {
		$localPath = "$($csvFilePath)/$($_.FileName)"
	}

	
	if (!(Test-Path $localPath)) {
		# File doesn't exist, simply download
		Write-Output "$(Get-Date) - File ($localPath) does not exist, simply downloading $($_.URL)"		
		DownloadFile -WebURL $_.URL -FileDirectory $csvFilePath -MD5 $_.MD5 -AltName $_.FileName
	}
	else {		
		# File exists, check MD5
		$fileHash = md5hash -path $localPath
		# Write-Output "$(Get-Date) - CSV MD5 Value: $($_.MD5)"
		# Write-Output "$(Get-Date) - File Path MD5 Value: $($fileHash)"
		if ($_.MD5 = $fileHash) {
			# No need to download again
			Write-Output "$(Get-Date) - MD5 matches, no need to redownload."		
		}
		else {
			# Need to redownload
			Write-Output "$(Get-Date) - MD5 Incorrect, attempting to download/redownload."
			try {
				Remove-Item -Path $localPath -Force
			}		
			catch {
				Write-Output "$(Get-Date) - MD5 Incorrect, unable to remove" 
			}
			DownloadFile -WebURL $_.URL -FileDirectory $csvFilePath -MD5 $_.MD5 -AltName $_.FileName
		}
	}
}
#endregion Use the CSV and download the files

$elapsedTime = $(get-date) - $StartTime
$totalTime = "{0:HH:mm:ss}" -f ([datetime]$elapsedTime.Ticks)
Write-Output "Process Execution Time: $totalTime" | Out-String

Stop-Transcript