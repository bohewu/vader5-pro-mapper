#requires -Version 7.2
param(
    [ValidateSet('Gui','Read','Apply','Test')][string]$Mode = 'Gui',
    [string]$Source,
    [string]$Target,
    [ValidateSet('Keep','Off','Hold','Toggle')][string]$TurboMode='Keep',
    [ValidateRange(1,20)][int]$TurboRate=15,
    [ValidateSet('Keep','On','Off')][string]$TurboMaster='Keep',
    [switch]$GuiChild,
    [ValidateRange(1,30)][int]$Seconds = 3
)
$ErrorActionPreference = 'Stop'
if ($Mode -eq 'Gui' -and -not $GuiChild) {
    # Hide only the launcher console; SW_HIDE must not hide the actual form.
    $start=[Diagnostics.ProcessStartInfo]::new()
    $start.FileName=(Get-Process -Id $PID).Path
    $start.UseShellExecute=$false
    $start.CreateNoWindow=$true
    foreach($argument in @('-NoProfile','-STA','-File',$PSCommandPath,'-GuiChild')){[void]$start.ArgumentList.Add($argument)}
    [void][Diagnostics.Process]::Start($start)
    exit
}
if (-not ('VaderLink' -as [type])) { Add-Type -Path (Join-Path $PSScriptRoot 'VaderLink.cs') }
$script:KeyIds = [ordered]@{ Up=0; Right=1; Down=2; Left=3; A=4; B=5; View=6; X=7; Y=8; Menu=9; LB=10; RB=11; LT=12; RT=13; L3=14; R3=15; C=16; Z=17; M1=18; M2=19; M3=20; M4=21; LM=22; RM=23 }
$script:Choices = [ordered]@{ '保留目前設定'=-1; '預設'=255; '停用遊戲輸出'=254; A=4; B=5; X=7; Y=8; LB=10; RB=11; LT=12; RT=13; L3=14; R3=15; Up=0; Down=2; Left=3; Right=1; View=6; Menu=9 }

function Open-Vader {
    if (Get-Process -Name 'Flydigi Space Station' -ErrorAction SilentlyContinue) { throw '請先從系統匣完整退出飛智空間站，再使用此工具。' }
    $service=Get-Service -Name 'Flydigi Space Station Service' -ErrorAction SilentlyContinue
    if($service -and $service.Status -eq 'Running'){throw '請先暫停飛智背景服務，避免配置被覆寫。在系統管理員 PowerShell 執行：Stop-Service -Name "Flydigi Space Station Service"。'}
    $devices = @(Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -like 'HID\VID_37D7&PID_2401&MI_01\*' })
    if ($devices.Count -ne 1) { throw '請連接一支黑武士 5 Pro（USB 線或接收器），並保持手把開機。' }
    $hidPath = '\\?\' + $devices[0].InstanceId.Replace('\','#').ToLowerInvariant() + '#{4d1e55b2-f16f-11cf-88cb-001111000030}'
    $wireless=$false
    $markers=@(Get-PnpDevice -PresentOnly|Where-Object {$_.InstanceId -like 'HID\VID_37D7&PID_2401&MI_03\*'})
    foreach($marker in $markers){$markerPath='\\?\'+$marker.InstanceId.Replace('\','#').ToLowerInvariant()+'#{4d1e55b2-f16f-11cf-88cb-001111000030}';if([VaderLink]::UsagePage($markerPath) -eq 0xFFEE){$wireless=$true}}
    [VaderLink]::new($hidPath,0,$wireless)
}
function Assert-Firmware($connection) {
    $info = $connection.Request(0x01)
    if ($info[5] -ne 130 -or $info[15] -ne 0x71 -or $info[16] -ne 0x54) { throw '此工具僅已驗證黑武士 5 Pro 韌體 7.1.5.4，其他版本停止寫入。' }
}
function Get-VaderState {
    $connection = Open-Vader
    try {
        Assert-Firmware $connection
        $versions = $connection.Request(0xA1)
        $hardware=$connection.Request(0x03)
        $profile = [int]$versions[5]
        if ($profile -gt 3) { throw '請使用 PC 模式的配置 1～4。' }
        $mapping = $connection.ReadBlob(0xA3,[byte]$profile)
        $second = $connection.ReadBlob(0xA3,[byte]$profile)
        if ([Convert]::ToHexString($mapping) -ne [Convert]::ToHexString($second)) { throw '兩次讀取不同；尚未寫入。請保持空間站關閉後重新讀取。' }
        if ($mapping.Length -ne 840 -or $mapping[0] -ne 2 -or $mapping[1] -ne 3) { throw '不支援此配置格式，已停止寫入。' }
        [pscustomobject]@{ Profile=$profile; Mapping=$mapping; Firmware='7.1.5.4'; TurboEnabled=(($hardware[6] -band 8) -ne 0);Connection=$(if($connection.Wireless){'USB 2.4G'}else{'USB'}) }
    } finally { $connection.Dispose() }
}
function New-VaderMapping([byte[]]$current,[System.Collections.IDictionary]$changes,[System.Collections.IDictionary]$turboChanges,[bool]$turboEnabled) {
    if($current.Length -ne 840 -or $current[0] -ne 2 -or $current[1] -ne 3){throw '不支援此配置格式。'}
    $desired=[byte[]]$current.Clone()
    foreach($key in $changes.Keys){
        if(-not $script:KeyIds.Contains($key)){throw "不支援的來源按鍵：$key"}
        $value=[int]$changes[$key]
        if($value -eq -1){continue}
        if($value -notin @($script:Choices.Values)){throw '不支援的輸出按鍵。'}
        $offset=13+3*$script:KeyIds[$key]
        if($desired[$offset] -ne $value){$desired[$offset]=[byte]$value;$desired[$offset+1]=0;$desired[$offset+2]=0}
    }
    foreach($key in $turboChanges.Keys){
        if(-not $script:KeyIds.Contains($key)){throw "不支援的連發來源：$key"}
        $mode=[int]$turboChanges[$key].Mode;$rate=[int]$turboChanges[$key].Rate
        if($mode -notin @(0,1,2) -or ($mode -ne 0 -and ($rate -lt 1 -or $rate -gt 20))){throw '連發模式或速度無效。'}
        $offset=13+3*$script:KeyIds[$key]
        if($mode -ne 0){
            if(-not $turboEnabled){throw '請勾選 Turbo 總開關，或使用 -TurboMaster On。'}
            if($desired[$offset] -eq 255){if($script:KeyIds[$key] -ge 16){throw "$key 請先選擇遊戲輸出按鍵，再設定連發。"};$desired[$offset]=[byte]$script:KeyIds[$key]}
            if($desired[$offset] -ge 32){throw "$key 的目前功能不支援直接連發；請先選擇一般手把輸出。"}
        }
        $desired[$offset+1]=[byte]$mode;$desired[$offset+2]=[byte]$(if($mode -eq 0){0}else{$rate})
    }
    return ,$desired
}
function Set-VaderState($state, [System.Collections.IDictionary]$changes, [System.Collections.IDictionary]$turboChanges=@{}, $master=$null) {
    $connection = Open-Vader
    $started = $false
    $masterChanged=$false
    $backupDir = $null
    try {
        Assert-Firmware $connection
        if ($connection.Request(0xA1)[5] -ne $state.Profile) { throw '手把已切換配置。請重新讀取後再儲存。' }
        $current = $connection.ReadBlob(0xA3,[byte]$state.Profile)
        if ([Convert]::ToHexString($current) -ne [Convert]::ToHexString($state.Mapping)) { throw '配置已被其他程式修改。請重新讀取後再調整。' }
        $hardware=$connection.Request(0x03);$originalMaster=($hardware[6] -band 8) -ne 0
        $desiredMaster=if($null -eq $master){$originalMaster}else{[bool]$master}
        $desired=New-VaderMapping $current $changes $turboChanges $desiredMaster
        $mappingChanged=[Convert]::ToHexString($desired) -ne [Convert]::ToHexString($current)
        if (-not $mappingChanged -and $desiredMaster -eq $originalMaster) { return '設定已相同，沒有重複寫入。' }
        $oldTag = [BitConverter]::ToUInt16($current,225)
        do { $tag = Get-Random -Minimum 0 -Maximum 65535 } while ($tag -eq $oldTag)
        if($mappingChanged){$desired[225]=[byte]($tag -band 255); $desired[226]=[byte]($tag -shr 8)}
        # Only explicitly edited button entries and the revision tag may differ.
        $allowed = [Collections.Generic.HashSet[int]]::new()
        foreach ($n in @(225,226)) { [void]$allowed.Add($n) }
        foreach ($key in $changes.Keys) { $base=13+3*$script:KeyIds[$key]; foreach($n in $base..($base+2)){ [void]$allowed.Add($n) } }
        foreach ($key in $turboChanges.Keys) { $base=13+3*$script:KeyIds[$key]; foreach($n in $base..($base+2)){ [void]$allowed.Add($n) } }
        for ($n=0; $n -lt 840; $n++) { if ($desired[$n] -ne $current[$n] -and -not $allowed.Contains($n)) { throw "未授權的配置變更：$n" } }
        $backupDir = Join-Path $PSScriptRoot ('backups\'+(Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
        [void](New-Item -ItemType Directory -Path $backupDir)
        [IO.File]::WriteAllBytes((Join-Path $backupDir 'mapping-before.bin'),$current)
        [ordered]@{ profile=$state.Profile+1; firmware=$state.Firmware; created=(Get-Date -Format o); sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($current)); requested=$changes;turboRequested=$turboChanges;previousTurboMaster=$originalMaster;requestedTurboMaster=$desiredMaster } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $backupDir 'backup.json') -Encoding utf8
        $after=$current
        if($mappingChanged){$started=$true;$after=$connection.WriteMapping([byte]$state.Profile,$desired)}
        if($desiredMaster -ne $originalMaster){$masterChanged=$true;[void]$connection.Request(0x13,4,[byte][int]$desiredMaster);$hardware=$connection.Request(0x03);if((($hardware[6] -band 8) -ne 0) -ne $desiredMaster){throw 'Turbo 總開關讀回驗證失敗。'}}
        [IO.File]::WriteAllBytes((Join-Path $backupDir 'mapping-after.bin'),$after)
        "配置 $($state.Profile+1) 已儲存並讀回驗證。備份：$backupDir"
    } catch {
        $failure = $_.Exception.Message
        if($masterChanged){try{[void]$connection.Request(0x13,4,[byte][int]$originalMaster)}catch{$failure+=' Turbo 總開關還原失敗。'}}
        if ($started) {
            try { [void]$connection.WriteMapping([byte]$state.Profile,$current); $failure += ' 已還原寫入前配置。' }
            catch { $failure += " 還原未完成：$($_.Exception.Message)。備份在 $backupDir" }
        }
        throw $failure
    } finally { $connection.Dispose() }
}
function Get-DisplayTarget([byte]$value) {
    if ($value -eq 32) { return '保留目前設定' }
    foreach ($choice in $script:Choices.Keys) { if ($script:Choices[$choice] -eq $value) { return $choice } }
    '保留目前設定'
}
if ($Mode -eq 'Read') {
    $state = Get-VaderState
    $buttons = foreach($key in $script:KeyIds.Keys) { $offset=13+3*$script:KeyIds[$key]; [ordered]@{ source=$key; target=$state.Mapping[$offset]; mode=$state.Mapping[$offset+1]; frequency=$state.Mapping[$offset+2] } }
    [ordered]@{ profile=$state.Profile+1; firmware=$state.Firmware; layout='3.2'; connection=$state.Connection; turboEnabled=$state.TurboEnabled; buttons=$buttons } | ConvertTo-Json -Depth 6
    exit
}
if ($Mode -eq 'Apply') {
    $Target=switch($Target){'Default'{'預設'} 'Disabled'{'停用遊戲輸出'} '停用'{'停用遊戲輸出'} 'Keep'{'保留目前設定'} default{$Target}}
    if (-not $Source -or -not $Target -or -not $script:Choices.Contains($Target)) { throw '請指定來源與輸出，例如 -Source C -Target A，或 -Target Disabled。' }
    $state=Get-VaderState
    $turbo=@{};if($TurboMode -ne 'Keep'){$modeValue=switch($TurboMode){'Off'{0}'Hold'{1}'Toggle'{2}};$turbo[$Source]=@{Mode=$modeValue;Rate=$TurboRate}}
    $masterValue=switch($TurboMaster){'On'{$true}'Off'{$false}default{$null}}
    Set-VaderState $state @{ $Source=[int]$script:Choices[$Target] } $turbo $masterValue
    exit
}
if ($Mode -eq 'Test') {
    $connection=Open-Vader
    $previousFlags=$null
    try {
        Assert-Firmware $connection
        $reportStatus=$connection.Request(0x10)
        $previousFlags=[byte[]]$reportStatus[5..9]
        [void]$connection.Request(0x11,255,1,255,255,255)
        $end=[DateTime]::UtcNow.AddSeconds($Seconds); $frames=0; $last=$null; $latest=$null
        while([DateTime]::UtcNow -lt $end){$report=$connection.Read(30);$raw=[VaderLink]::RawInput($report);if($null -ne $raw){$latest=$raw;$frames++};$output=[VaderLink]::GameOutput();$description="raw=$($latest.Pressed); output=$($output.Pressed)";if($description -ne $last){[pscustomobject]@{time=(Get-Date -Format 'HH:mm:ss.fff');rawButtons=$latest.Pressed;outputButtons=$output.Pressed;outputSlot=$output.Slot;outputConnected=$output.Connected}|ConvertTo-Json -Compress;$last=$description}}
        if($frames -eq 0){throw '沒有收到原始按鍵資料。'}
        "Raw frames received: $frames"
    } finally {if($previousFlags){try{[void]$connection.Request(0x11,$previousFlags)}catch{Write-Warning '裝置已斷線；重新插入可結束原始測試模式。'}};$connection.Dispose()}
    exit
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$form=[Windows.Forms.Form]::new(); $form.Text='Vader5 Pro Mapper — 改鍵與測試'; $form.Size=[Drawing.Size]::new(780,850); $form.MinimumSize=[Drawing.Size]::new(700,600); $form.StartPosition='CenterScreen'; $form.Font=[Drawing.Font]::new('Microsoft JhengHei UI',10);$form.AutoScaleMode='Dpi'
$tabs=[Windows.Forms.TabControl]::new();$tabs.Dock='Fill';$editor=[Windows.Forms.TabPage]::new('按鍵映射');$testPage=[Windows.Forms.TabPage]::new('按鍵測試');$tabs.TabPages.Add($editor);$tabs.TabPages.Add($testPage);$form.Controls.Add($tabs)
$editorLayout=[Windows.Forms.TableLayoutPanel]::new();$editorLayout.Dock='Fill';$editorLayout.Padding=[Windows.Forms.Padding]::new(12);$editorLayout.ColumnCount=1;$editorLayout.RowCount=5
[void]$editorLayout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,100))
foreach($kind in @('AutoSize','Percent','AutoSize','AutoSize','AutoSize')){[void]$editorLayout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::$kind,100))};$editor.Controls.Add($editorLayout)
$hint=[Windows.Forms.Label]::new();$hint.AutoSize=$true;$hint.Dock='Fill';$hint.Text="選擇按鍵輸出與連發模式，再儲存至目前配置。`n未修改的按鍵會保留原設定。";$editorLayout.Controls.Add($hint,0,0)
$grid=[Windows.Forms.DataGridView]::new();$grid.Dock='Fill';$grid.AllowUserToAddRows=$false;$grid.AllowUserToDeleteRows=$false;$grid.RowHeadersVisible=$false;$grid.AutoSizeColumnsMode='Fill';$grid.SelectionMode='CellSelect';$grid.BackgroundColor=[Drawing.Color]::White;$grid.EditMode='EditOnEnter';$grid.DefaultCellStyle.BackColor=[Drawing.Color]::White;$grid.DefaultCellStyle.ForeColor=[Drawing.Color]::Black;$grid.DefaultCellStyle.SelectionBackColor=[Drawing.Color]::LightBlue;$grid.DefaultCellStyle.SelectionForeColor=[Drawing.Color]::Black;$grid.RowTemplate.Height=28
$sourceColumn=[Windows.Forms.DataGridViewTextBoxColumn]::new(); $sourceColumn.HeaderText='實體來源按鍵'; $sourceColumn.ReadOnly=$true; [void]$grid.Columns.Add($sourceColumn)
$targetColumn=[Windows.Forms.DataGridViewComboBoxColumn]::new();$targetColumn.HeaderText='輸出映射';$targetColumn.FlatStyle='Standard';foreach($choice in $script:Choices.Keys){[void]$targetColumn.Items.Add($choice)};[void]$grid.Columns.Add($targetColumn);$editorLayout.Controls.Add($grid,0,1)
$modeColumn=[Windows.Forms.DataGridViewComboBoxColumn]::new();$modeColumn.HeaderText='連發模式';$modeColumn.FlatStyle='Standard';[void]$modeColumn.Items.AddRange([object[]]@('關閉','按住連發','按一下切換'));[void]$grid.Columns.Add($modeColumn)
$rateColumn=[Windows.Forms.DataGridViewTextBoxColumn]::new();$rateColumn.HeaderText='次／秒';$rateColumn.FillWeight=45;[void]$grid.Columns.Add($rateColumn)
$grid.Add_EditingControlShowing({param($sender,$eventArgs)
    if($eventArgs.Control -is [Windows.Forms.ComboBox]){
        $combo=$eventArgs.Control;$combo.BackColor=[Drawing.Color]::White;$combo.ForeColor=[Drawing.Color]::Black;$combo.FlatStyle='Standard';$combo.DrawMode='OwnerDrawFixed'
        if($combo.Tag -ne 'VaderReadableDropdown'){
            $combo.Tag='VaderReadableDropdown'
            $combo.Add_DrawItem({param($control,$draw)
                if($draw.Index -lt 0){return}
                $selected=($draw.State -band [Windows.Forms.DrawItemState]::Selected) -ne 0
                $background=if($selected){[Drawing.Brushes]::RoyalBlue}else{[Drawing.Brushes]::White}
                $foreground=if($selected){[Drawing.Color]::White}else{[Drawing.Color]::Black}
                $draw.Graphics.FillRectangle($background,$draw.Bounds)
                [Windows.Forms.TextRenderer]::DrawText($draw.Graphics,[string]$control.Items[$draw.Index],$control.Font,$draw.Bounds,$foreground,([Windows.Forms.TextFormatFlags]::Left -bor [Windows.Forms.TextFormatFlags]::VerticalCenter))
                $draw.DrawFocusRectangle()
            })
        }
    }
})
$toolbar=[Windows.Forms.FlowLayoutPanel]::new();$toolbar.AutoSize=$true;$toolbar.Dock='Fill';$toolbar.WrapContents=$false;$editorLayout.Controls.Add($toolbar,0,2)
$load=[Windows.Forms.Button]::new();$load.Text='重新讀取';$load.AutoSize=$true;$load.MinimumSize=[Drawing.Size]::new(120,36);$toolbar.Controls.Add($load)
$save=[Windows.Forms.Button]::new();$save.Text='儲存到手把';$save.AutoSize=$true;$save.MinimumSize=[Drawing.Size]::new(150,36);$save.Enabled=$false;$toolbar.Controls.Add($save)
$masterToggle=[Windows.Forms.CheckBox]::new();$masterToggle.Text='Turbo 總開關（所有配置）';$masterToggle.AutoSize=$true;$masterToggle.Margin=[Windows.Forms.Padding]::new(16,10,0,0);$toolbar.Controls.Add($masterToggle)
$status=[Windows.Forms.Label]::new();$status.AutoSize=$true;$status.Dock='Fill';$status.Text='尚未連接。';$editorLayout.Controls.Add($status,0,3)
$foot=[Windows.Forms.Label]::new();$foot.AutoSize=$true;$foot.Dock='Fill';$foot.Text="連發速度 1～20 次／秒。巨集與鍵鼠功能可保留，此工具不編輯它們。`n「停用遊戲輸出」不會清除既有鍵盤／滑鼠綁定。";$foot.Font=[Drawing.Font]::new('Microsoft JhengHei UI',8);$editorLayout.Controls.Add($foot,0,4)
$script:LoadedState=$null
$script:LoadingGrid=$false
$script:DraftChanged=$false
$statusTip=[Windows.Forms.ToolTip]::new();$statusTip.SetToolTip($load,'重新讀取手把配置；尚未儲存的修改會被捨棄。')
$markDirty={if($script:LoadedState -and -not $script:LoadingGrid){$script:DraftChanged=$true;$status.Text="配置 $($script:LoadedState.Profile+1) 有未儲存變更。"}}
$grid.Add_CurrentCellDirtyStateChanged({if($grid.IsCurrentCellDirty){[void]$grid.CommitEdit([Windows.Forms.DataGridViewDataErrorContexts]::Commit)}})
$grid.Add_CellValueChanged($markDirty)
$masterToggle.Add_CheckedChanged($markDirty)
$reload={
    $load.Enabled=$false; $save.Enabled=$false; $form.UseWaitCursor=$true
    $script:LoadingGrid=$true
    $script:ReloadSucceeded=$false
    try {
        $script:LoadedState=Get-VaderState
        $grid.Rows.Clear()
        foreach($key in $script:KeyIds.Keys){
            $offset=13+3*$script:KeyIds[$key];$display=Get-DisplayTarget $script:LoadedState.Mapping[$offset]
            $mode=[int]$script:LoadedState.Mapping[$offset+1];$rate=[int]$script:LoadedState.Mapping[$offset+2]
            $modeLabel=switch($mode){1{'按住連發'}2{'按一下切換'}default{'關閉'}}
            $row=$grid.Rows.Add($key,$display,$modeLabel,$rate);$grid.Rows[$row].Tag=[pscustomobject]@{Key=$key;Target=$display;Mode=$modeLabel;Rate=[string]$rate}
        }
        $masterToggle.Checked=$script:LoadedState.TurboEnabled
        $script:DraftChanged=$false
        $status.Text="配置 $($script:LoadedState.Profile+1) · $($script:LoadedState.Connection) · 韌體 $($script:LoadedState.Firmware) · 已讀取"
        $save.Enabled=$true
        $script:ReloadSucceeded=$true
    } catch { $status.Text='讀取失敗：'+$_.Exception.GetBaseException().Message }
    finally { $script:LoadingGrid=$false;$load.Enabled=$true; $form.UseWaitCursor=$false }
}
$load.Add_Click({if($script:DraftChanged -and [Windows.Forms.MessageBox]::Show($form,'捨棄未儲存的修改，重新讀取手把配置？','重新讀取','YesNo','Question') -ne 'Yes'){return};& $reload})
$save.Add_Click({
    $load.Enabled=$false; $save.Enabled=$false; $form.UseWaitCursor=$true
    try {
        [void]$grid.EndEdit();$changes=[ordered]@{};$turboChanges=[ordered]@{}
        foreach($row in $grid.Rows){
            $original=$row.Tag;$key=$original.Key;$choice=[string]$row.Cells[1].Value;$value=[int]$script:Choices[$choice]
            $targetChanged=$choice -ne $original.Target -and $value -ne -1
            $modeLabel=[string]$row.Cells[2].Value;$rateText=[string]$row.Cells[3].Value
            $turboEdited=$modeLabel -ne $original.Mode -or $rateText -ne $original.Rate
            if(-not $targetChanged -and -not $turboEdited){continue}
            if($targetChanged){$changes[$key]=$value}
            $mode=switch($modeLabel){'按住連發'{1}'按一下切換'{2}default{0}}
            $rate=if($mode -eq 0){0}else{[int]$row.Cells[3].Value}
            $turboChanges[$key]=@{Mode=$mode;Rate=$rate}
        }
        $message=Set-VaderState $script:LoadedState $changes $turboChanges $masterToggle.Checked
        & $reload
        if($script:ReloadSucceeded){$status.Text=if($message -eq '設定已相同，沒有重複寫入。'){$message}else{"配置 $($script:LoadedState.Profile+1) 已儲存、備份並驗證。"}}
        $statusTip.SetToolTip($status,$message)
    }
    catch { $status.Text=$_.Exception.Message; $save.Enabled=$true }
    finally {$load.Enabled=$true;$form.UseWaitCursor=$false}
})
$testLayout=[Windows.Forms.TableLayoutPanel]::new();$testLayout.Dock='Fill';$testLayout.Padding=[Windows.Forms.Padding]::new(12);$testLayout.ColumnCount=1;$testLayout.RowCount=5
[void]$testLayout.ColumnStyles.Add([Windows.Forms.ColumnStyle]::new([Windows.Forms.SizeType]::Percent,100))
foreach($kind in @('AutoSize','AutoSize','Percent','Percent','AutoSize')){[void]$testLayout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::$kind,50))};$testPage.Controls.Add($testLayout)
$testHint=[Windows.Forms.Label]::new();$testHint.AutoSize=$true;$testHint.Dock='Fill';$testHint.Text="比較實體按鍵與映射後的遊戲輸出。`n依序按放按鍵，檢查映射、連發、搖桿與扳機反應。";$testLayout.Controls.Add($testHint,0,0)
$testButton=[Windows.Forms.Button]::new();$testButton.AutoSize=$true;$testButton.MinimumSize=[Drawing.Size]::new(140,36);$testButton.Text='開始測試';$testLayout.Controls.Add($testButton,0,1)
$rawGroup=[Windows.Forms.GroupBox]::new();$rawGroup.Text='實體原始訊號';$rawGroup.Dock='Fill';$testLayout.Controls.Add($rawGroup,0,2)
$rawLayout=[Windows.Forms.TableLayoutPanel]::new();$rawLayout.Dock='Fill';$rawLayout.Padding=[Windows.Forms.Padding]::new(8,16,8,8);$rawLayout.ColumnCount=1;$rawLayout.RowCount=2;[void]$rawLayout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize));[void]$rawLayout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,100));$rawGroup.Controls.Add($rawLayout)
$rawSummary=[Windows.Forms.Label]::new();$rawSummary.AutoSize=$true;$rawSummary.Dock='Fill';$rawSummary.Text='等待實體按鍵資料';$rawLayout.Controls.Add($rawSummary,0,0)
$rawText=[Windows.Forms.TextBox]::new();$rawText.Dock='Fill';$rawText.Multiline=$true;$rawText.ReadOnly=$true;$rawText.ScrollBars='Vertical';$rawText.Font=[Drawing.Font]::new('Consolas',11);$rawLayout.Controls.Add($rawText,0,1)
$outputGroup=[Windows.Forms.GroupBox]::new();$outputGroup.Text='遊戲收到的輸出（XInput）';$outputGroup.Dock='Fill';$testLayout.Controls.Add($outputGroup,0,3)
$outputLayout=[Windows.Forms.TableLayoutPanel]::new();$outputLayout.Dock='Fill';$outputLayout.Padding=[Windows.Forms.Padding]::new(8,16,8,8);$outputLayout.ColumnCount=1;$outputLayout.RowCount=2;[void]$outputLayout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::AutoSize));[void]$outputLayout.RowStyles.Add([Windows.Forms.RowStyle]::new([Windows.Forms.SizeType]::Percent,100));$outputGroup.Controls.Add($outputLayout)
$outputSummary=[Windows.Forms.Label]::new();$outputSummary.AutoSize=$true;$outputSummary.Dock='Fill';$outputSummary.Text='等待遊戲輸出';$outputLayout.Controls.Add($outputSummary,0,0)
$outputText=[Windows.Forms.TextBox]::new();$outputText.Dock='Fill';$outputText.Multiline=$true;$outputText.ReadOnly=$true;$outputText.ScrollBars='Vertical';$outputText.Font=[Drawing.Font]::new('Consolas',11);$outputLayout.Controls.Add($outputText,0,1)
$testStatus=[Windows.Forms.Label]::new();$testStatus.AutoSize=$true;$testStatus.Dock='Fill';$testStatus.Text='離開本頁或關閉工具時，會恢復原始資料串流的先前狀態。';$testLayout.Controls.Add($testStatus,0,4)
$script:TestLink=$null;$script:TestFlags=$null;$script:LatestRaw=$null
$timer=[Windows.Forms.Timer]::new();$timer.Interval=50
$stopTest={
    $timer.Stop()
    if($script:TestLink){try{if($script:TestFlags){[void]$script:TestLink.Request(0x11,$script:TestFlags)}}catch{$testStatus.Text='裝置已斷線；重新插入可結束測試模式。'}finally{$script:TestLink.Dispose();$script:TestLink=$null}}
    $testButton.Text='開始測試'
    $script:TestFlags=$null
    if($testStatus.Text -eq '測試中。不會儲存或更改按鍵映射。'){$testStatus.Text='測試已停止，原始資料串流已恢復原狀。'}
}
$startTest={
    & $stopTest
    try{$script:TestLink=Open-Vader;Assert-Firmware $script:TestLink;$reportStatus=$script:TestLink.Request(0x10);$script:TestFlags=[byte[]]$reportStatus[5..9];[void]$script:TestLink.Request(0x11,255,1,255,255,255);$script:LatestRaw=$null;$testButton.Text='停止測試';$testStatus.Text='測試中。不會儲存或更改按鍵映射。';$timer.Start()}
    catch{$testStatus.Text=$_.Exception.Message;& $stopTest}
}
$formatInput={param($view) "Pressed: $($view.Pressed)`r`n`r`nLX: $($view.LX)    LY: $($view.LY)`r`nRX: $($view.RX)    RY: $($view.RY)`r`nLT: $($view.LT)    RT: $($view.RT)"}
$timer.Add_Tick({
    try{
        for($i=0;$i -lt 100;$i++){$report=$script:TestLink.Read(0);if($null -eq $report){break};$v=[VaderLink]::RawInput($report);if($null -ne $v){$script:LatestRaw=$v}}
        if($script:LatestRaw){$rawText.Text=& $formatInput $script:LatestRaw;$pressed=if($script:LatestRaw.Pressed){$script:LatestRaw.Pressed}else{'無'};$rawSummary.Text="實體按下：$pressed"}
        $out=[VaderLink]::GameOutput()
        if($out.Connected){$outputText.Text=& $formatInput $out;$pressed=if($out.Pressed){$out.Pressed}else{'無'};$outputSummary.Text="XInput 槽位 $($out.Slot) · 輸出按下：$pressed"}else{$outputSummary.Text='XInput 手把未連接';$outputText.Text=''}
    }catch{$testStatus.Text=$_.Exception.Message;& $stopTest}
})
$testButton.Add_Click({if($script:TestLink){& $stopTest}else{& $startTest}})
$tabs.Add_SelectedIndexChanged({if($tabs.SelectedIndex -eq 1){& $startTest}else{& $stopTest}})
$form.Add_FormClosing({param($sender,$eventArgs)if($script:DraftChanged -and [Windows.Forms.MessageBox]::Show($form,'捨棄未儲存的修改並關閉？','關閉工具','YesNo','Question') -ne 'Yes'){$eventArgs.Cancel=$true;return};& $stopTest;$timer.Dispose();$statusTip.Dispose()})
$form.Add_Shown($reload)
[void]$form.ShowDialog()
$form.Dispose()
