Clear
"##################"
" 4chan downloader"
"##################";""

########################################################
# Change to where you want the wallpapers to be stored #
########################################################
$SavePath="$($env:USERPROFILE)\Desktop\Scrape"
########################################################

$threadUri = "https://boards.4chan.org/"
$Response = Invoke-WebRequest -Uri $threadUri;
$Boards = $($Response.links) | ?{$_.Class -eq "BoardLink" -and $_.href -notlike "*thread*"}
$BoardsArray = @();$ID=1
foreach($Record in $($Boards | Select href,innertext | Sort innerText))
{
    "$id - $($Record.innerText)"
    $recordinfo = New-Object psobject -Property @{
	    ID = $ID
        boardname = $Record.innerText
        href = "http:$($Record.href)"
    }
    $BoardsArray += $recordinfo 
    $ID++
}
$Prompt = read-host "Which board would you like to extract images from? [ID]"
if($prompt -eq "")
{
    $Selection = $Selection 
}
else
{
    $Selection = $($BoardsArray | ?{$_.ID -eq $Prompt}).href
}
if($Selection -eq ""){ Break }
clear
write-host -f Red $(($BoardsArray | ?{$_.href -eq "$Selection"}).boardname)
$Temp = $selection.split('/')[3]

$SaveDestination = "$SavePath\$Temp\"
if (!(Test-Path $SaveDestination))
{
    write-host -f yellow "Creating root directory ($SaveDestination)"
    New-Item -ItemType  Directory -Path $SaveDestination | Out-Null;
}

$ID=1
while($ID -le 10)
{
    if($ID -eq '1')
    {
        $URLID=$null
    }
    else
    {
        $URLID=$ID
    }
    $threadUri = "https://boards.4chan.org/$Temp/$URLID"
    write-host -f darkyellow $threadUri
    try
    {
        $Response = Invoke-WebRequest -Uri $threadUri;
    }
    catch
    {
        
        Write-Host "Connection error: `n";
        Write-Host $error[0].Exception;
        Write-Host "`nCheck the error message above";
        exit; 
    }
   
    $threads = $($Response.links).href | ?{$_ -like "thread/*" -and $_ -notlike "thread/*/*" -and $_ -notlike "*#*"} | Select -unique | Sort 
    foreach($thread in $threads)
    {
        $ThreadURI = "https://boards.4chan.org/$Temp/$thread"
        $ThreadID = $thread.replace("thread/","")
        write-host -f yellow "  $ThreadURI"
        try
        {
            $Response = Invoke-WebRequest -Uri $threadUri;
        }
        catch
        {
        
            Write-Host "Connection error: `n";
            Write-Host $error[0].Exception;
            Write-Host "`nCheck the error message above";
            #exit; 
        }

        $title = $($Response.ParsedHtml.getElementsByTagName('title')).innertext;
        $title = $title -replace '^\/.*\/ - (.*) - .* - .*$','$1';
        $dirName = $title -replace '[^a-zA-Z0-9]','-';

        $html = $Response.Links.Href;

        $regex = "^.*(\.jpg$)|(\.png$)|(\.gif$)|(\.webm$)";

        if (!(Test-Path $SaveDestination\$dirName))
        {
            write-host -f yellow "    Creating directory - $dirName"
            New-Item -ItemType  Directory -Path $SaveDestination\$dirName | Out-Null;
        }
        else
        {
            write-host -f green "    Existing thread - $dirName"
        }
        $counter = 0;
        foreach ($currentHref in $html) {
            if ($currentHref -match $regex) 
            {
                $Uri = 'http:' + $currentHref;
                $fileName = $currentHref -replace '^.*/(\d+\.[a-zA-Z]{3})','$1';
	            if([System.IO.File]::Exists("$SaveDestination\$dirName\$fileName")) { continue; }
	            "      Downloading $fileName"
                Invoke-WebRequest -Uri $Uri -OutFile "$SaveDestination\$dirName\$fileName";
	            $counter++;
            }
        }
        "    $counter new images downloaded `n    $SaveDestination$dirName`n ";
    }
    $ID++
}
